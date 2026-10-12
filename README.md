# IPTV Player

Player de IPTV nativo para macOS (SwiftUI + libmpv). Suporta listas M3U e contas Xtream Codes.

## Compilar

```sh
./scripts/build-app.sh          # gera build/IPTV Player.app
./scripts/make-dmg.sh           # gera build/IPTV-Player-<versão>.dmg para partilhar
open "build/IPTV Player.app"
```

O libmpv e o FFmpeg vêm do [MPVKit](https://github.com/mpvkit/MPVKit) (pré-compilados, LGPL) e ficam
ligados estaticamente, por isso a app não precisa do Homebrew.

Para desenvolvimento: `swift build` (com só as Command Line Tools, usa
`SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk swift build`; o SDK do macOS 27
precisa do Xcode completo por causa das macros do SwiftUI).

`IPTV_AUTOPLAY=<url> .build/debug/IPTVPlayer` abre logo o player com esse stream (só em debug).

## Atalhos no player

| Tecla | Ação |
|---|---|
| Espaço / clique | Pausa |
| Duplo clique / F | Ecrã inteiro |
| ↑ ↓ | Canal anterior / seguinte |
| ← → (⇧ para 1 min) | Recuar / avançar 10 s |
| M | Silenciar |
| + − | Volume |
| L | Lista de canais |

## Notas

- Requer Apple Silicon e macOS 15+. Não há build Intel: o Swift das Command Line Tools do macOS 27
  já não inclui o runtime x86_64.
- A app não é assinada pela Apple: quem a recebe tem de a autorizar em Definições do Sistema →
  Privacidade e Segurança → "Abrir na mesma" (explicado no `Como abrir.txt` do .dmg).
- As fontes (incluindo passwords) ficam em `~/Library/Application Support/IPTVPlayer/sources.json`,
  legível apenas pelo teu utilizador. A biblioteca fica em cache durante 12 h (⌘R atualiza).
