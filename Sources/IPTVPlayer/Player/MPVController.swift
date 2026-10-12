import AppKit
import Libmpv
import OpenGL.GL3

enum PlayerDefaults {
    /// Many IPTV providers reject unknown clients, but almost all allow VLC.
    static let userAgent = "VLC/3.0.21 LibVLC/3.0.21"
}

enum MPVEvent {
    case property(String, Any?)
    case startFile
    case fileLoaded
    case endFile(error: String?, endOfFile: Bool)
}

/// Thin wrapper around a libmpv core. Video is drawn through the render API into `MPVVideoLayer`.
final class MPVController: @unchecked Sendable {
    private var handle: OpaquePointer?
    private var renderContext: OpaquePointer?
    private var glContext: CGLContextObj?
    private weak var layer: CAOpenGLLayer?
    private let eventQueue = DispatchQueue(label: "iptv.mpv.events")
    /// A load requested before the video layer exists; replayed once rendering is ready,
    /// otherwise mpv would fail to create its video output and play audio only.
    private var pendingLoad: (() -> Void)?

    /// Called on the main thread.
    var onEvent: ((MPVEvent) -> Void)?

    init() {
        setlocale(LC_NUMERIC, "C")
        handle = mpv_create()
        guard let handle else { fatalError("mpv_create failed") }

        let options: [(String, String)] = [
            ("vo", "libmpv"),
            ("hwdec", "auto-safe"),
            ("idle", "yes"),
            ("keep-open", "no"),
            ("config", "no"),
            ("terminal", "no"),
            ("osc", "no"),
            ("input-default-bindings", "no"),
            ("input-vo-keyboard", "no"),
            ("ytdl", "no"),
            ("audio-client-name", "IPTV Player"),
            ("user-agent", PlayerDefaults.userAgent),
            ("cache", "yes"),
            ("demuxer-max-bytes", "150MiB"),
            ("demuxer-readahead-secs", "20"),
            ("network-timeout", "20"),
            ("stream-lavf-o", "reconnect=1,reconnect_streamed=1,reconnect_delay_max=5"),
            ("alang", "por,pt,eng,en"),
            ("slang", "por,pt,pob"),
            ("sub-font-size", "44"),
            ("sub-border-size", "2.5"),
            ("volume-max", "150"),
        ]
        for (key, value) in options { mpv_set_option_string(handle, key, value) }

        mpv_initialize(handle)

        for (name, format) in [
            ("pause", MPV_FORMAT_FLAG), ("paused-for-cache", MPV_FORMAT_FLAG), ("core-idle", MPV_FORMAT_FLAG),
            ("time-pos", MPV_FORMAT_DOUBLE), ("duration", MPV_FORMAT_DOUBLE), ("cache-buffering-state", MPV_FORMAT_INT64),
            ("volume", MPV_FORMAT_DOUBLE), ("mute", MPV_FORMAT_FLAG),
            ("track-list/count", MPV_FORMAT_INT64), ("aid", MPV_FORMAT_STRING), ("sid", MPV_FORMAT_STRING),
            ("video-params/w", MPV_FORMAT_INT64), ("video-params/h", MPV_FORMAT_INT64),
        ] {
            mpv_observe_property(handle, 0, name, format)
        }

        mpv_set_wakeup_callback(handle, { ctx in
            let me = Unmanaged<MPVController>.fromOpaque(ctx!).takeUnretainedValue()
            me.eventQueue.async { me.drainEvents() }
        }, Unmanaged.passUnretained(self).toOpaque())
    }

    // MARK: Commands

    func load(_ url: URL, userAgent: String?, referrer: String?) {
        let action = { [weak self] in
            guard let self else { return }
            setString("user-agent", userAgent ?? PlayerDefaults.userAgent)
            setString("referrer", referrer ?? "")
            command(["loadfile", url.isFileURL ? url.path() : url.absoluteString, "replace"])
        }
        if renderContext == nil {
            pendingLoad = action
        } else {
            action()
        }
    }

    func stop() {
        pendingLoad = nil
        command(["stop"])
    }

    func command(_ args: [String]) {
        guard let handle else { return }
        let cStrings = args.map { strdup($0) }
        defer { cStrings.forEach { free($0) } }
        var argv: [UnsafePointer<CChar>?] = cStrings.map { UnsafePointer($0) } + [nil]
        mpv_command_async(handle, 0, &argv)
    }

    func setString(_ name: String, _ value: String) {
        guard let handle else { return }
        mpv_set_property_string(handle, name, value)
    }

    func setFlag(_ name: String, _ value: Bool) { setString(name, value ? "yes" : "no") }
    func setDouble(_ name: String, _ value: Double) { setString(name, String(value)) }

    func getString(_ name: String) -> String? {
        guard let handle, let ptr = mpv_get_property_string(handle, name) else { return nil }
        defer { mpv_free(ptr) }
        return String(cString: ptr)
    }

    func shutdown() {
        detachRender()
        if let handle {
            mpv_set_wakeup_callback(handle, nil, nil)
            mpv_terminate_destroy(handle)
        }
        handle = nil
    }

    // MARK: Events

    private func drainEvents() {
        while let handle, let event = mpv_wait_event(handle, 0)?.pointee {
            switch event.event_id {
            case MPV_EVENT_NONE, MPV_EVENT_SHUTDOWN:
                return
            case MPV_EVENT_PROPERTY_CHANGE:
                guard let data = event.data else { continue }
                let prop = data.assumingMemoryBound(to: mpv_event_property.self).pointee
                let name = String(cString: prop.name)
                var value: Any?
                if let p = prop.data {
                    switch prop.format {
                    case MPV_FORMAT_FLAG: value = p.assumingMemoryBound(to: CInt.self).pointee != 0
                    case MPV_FORMAT_DOUBLE: value = p.assumingMemoryBound(to: Double.self).pointee
                    case MPV_FORMAT_INT64: value = p.assumingMemoryBound(to: Int64.self).pointee
                    case MPV_FORMAT_STRING: value = p.assumingMemoryBound(to: UnsafePointer<CChar>?.self).pointee.map { String(cString: $0) }
                    default: break
                    }
                }
                emit(.property(name, value))
            case MPV_EVENT_START_FILE:
                emit(.startFile)
            case MPV_EVENT_FILE_LOADED:
                emit(.fileLoaded)
            case MPV_EVENT_END_FILE:
                guard let data = event.data else { continue }
                let end = data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
                if end.reason == MPV_END_FILE_REASON_ERROR {
                    emit(.endFile(error: String(cString: mpv_error_string(end.error)), endOfFile: false))
                } else if end.reason == MPV_END_FILE_REASON_EOF {
                    emit(.endFile(error: nil, endOfFile: true))
                }
            default:
                continue
            }
        }
    }

    private func emit(_ event: MPVEvent) {
        DispatchQueue.main.async { [weak self] in self?.onEvent?(event) }
    }

    // MARK: Rendering (called on the main thread by MPVVideoLayer)

    func attachRender(glContext: CGLContextObj, layer: CAOpenGLLayer) {
        guard let handle else { return }
        detachRender()
        self.glContext = glContext
        self.layer = layer
        CGLSetCurrentContext(glContext)

        let apiType = strdup(MPV_RENDER_API_TYPE_OPENGL)
        defer { free(apiType) }
        var initParams = mpv_opengl_init_params(get_proc_address: glProcAddress, get_proc_address_ctx: nil)
        var ctx: OpaquePointer?
        let status = withUnsafeMutablePointer(to: &initParams) { initPtr in
            var params = [
                mpv_render_param(type: MPV_RENDER_PARAM_API_TYPE, data: apiType),
                mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, data: initPtr),
                mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
            ]
            return mpv_render_context_create(&ctx, handle, &params)
        }
        guard status >= 0, let ctx else {
            NSLog("mpv_render_context_create failed: \(String(cString: mpv_error_string(status)))")
            return
        }
        renderContext = ctx
        mpv_render_context_set_update_callback(ctx, { ctx in
            let me = Unmanaged<MPVController>.fromOpaque(ctx!).takeUnretainedValue()
            DispatchQueue.main.async { me.layer?.setNeedsDisplay() }
        }, Unmanaged.passUnretained(self).toOpaque())

        if let pendingLoad {
            self.pendingLoad = nil
            pendingLoad()
        }
    }

    func detachRender() {
        guard let renderContext else { return }
        mpv_render_context_set_update_callback(renderContext, nil, nil)
        if let glContext { CGLSetCurrentContext(glContext) }
        mpv_render_context_free(renderContext)
        self.renderContext = nil
        glContext = nil
        layer = nil
    }

    var isRenderReady: Bool { renderContext != nil }

    func render(fbo: GLint, width: GLint, height: GLint) {
        guard let renderContext else { return }
        var target = mpv_opengl_fbo(fbo: Int32(fbo), w: Int32(width), h: Int32(height), internal_format: 0)
        var flipY: CInt = 1
        withUnsafeMutablePointer(to: &target) { targetPtr in
            withUnsafeMutablePointer(to: &flipY) { flipPtr in
                var params = [
                    mpv_render_param(type: MPV_RENDER_PARAM_OPENGL_FBO, data: targetPtr),
                    mpv_render_param(type: MPV_RENDER_PARAM_FLIP_Y, data: flipPtr),
                    mpv_render_param(type: MPV_RENDER_PARAM_INVALID, data: nil),
                ]
                mpv_render_context_render(renderContext, &params)
            }
        }
    }
}

private func glProcAddress(_ ctx: UnsafeMutableRawPointer?, _ name: UnsafePointer<CChar>?) -> UnsafeMutableRawPointer? {
    guard let name else { return nil }
    let symbol = CFStringCreateWithCString(kCFAllocatorDefault, name, CFStringBuiltInEncodings.ASCII.rawValue)
    guard let bundle = CFBundleGetBundleWithIdentifier("com.apple.opengl" as CFString) else { return nil }
    return CFBundleGetFunctionPointerForName(bundle, symbol)
}
