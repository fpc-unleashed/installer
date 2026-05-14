# Unleashed Installer

Official installer for the [fpc-unleashed](https://github.com/fpc-unleashed) project. Downloads source, builds FPC Unleashed and Lazarus IDE into a self-contained directory of your choice. No registry side effects, no PATH modification, no overwriting of system FPC.

## Release artifacts

- `installer_win64_x86_64.exe` -- Windows host
- `installer_linux_x86_64` -- Linux host (raw ELF64)
- `installer_linux_x86_64.AppImage` -- Linux host (AppImage, self-contained)

All three are published to the `nightly` release; pick whichever suits your distro / preference.

## What the installer does

Pick a target directory, optionally pin commits, tick the cross compilers you want, click **Install**. The installer then:

1. Downloads a bootstrap FPC and the FPC Unleashed + Lazarus source.
2. Builds the native FPC for the host OS, then any cross targets you ticked.
3. Builds the Lazarus IDE and any optional addons you ticked.
4. Drops a desktop shortcut to the IDE, wired to a per-install Lazarus config so the install stays isolated from anything else on the system.

Re-runs are idempotent: unchanged components self-skip, ticked-but-missing targets get filled in, unticked-but-present targets get removed, addon toggles trigger a surgical IDE rebuild. State lives in `<install>/installer.ini`.

Install dir defaults: `C:\fpcunleashed\` on Windows, `$HOME/fpcunleashed/` on Linux.

## Cross-target support matrix

| Target          | From win64 host | From linux64 host                            |
| --------------- | --------------- | -------------------------------------------- |
| `x86_64-win64`  | native          | cross via FPC internal PE/COFF linker (-Xi)  |
| `x86_64-linux`  | cross           | native                                       |
| `i386-win32`    | cross           | cross                                        |
| `i386-linux`    | cross           | cross; needs `i386-win32` as prereq          |
| `wasm32-wasip1` | cross           | cross                                        |

## Linux host requirements

The native compile and Lazarus GTK2 build need a working toolchain on the host:

```sh
# Debian / Ubuntu / Mint
sudo apt install -y curl build-essential libgtk2.0-dev xdg-utils

# Fedora
sudo dnf install -y curl make gcc binutils gtk2-devel xdg-utils

# Arch / Manjaro
sudo pacman -S --needed curl base-devel gtk2 xdg-utils
```

Tested baseline: glibc 2.28+ (Ubuntu 18.04+, Debian 10+, Fedora 29+).

## License

Source published for audit. See [LICENSE](LICENSE) -- free to run, free to read, free to build yourself, no forks.
