{
  description = "Linux 6.16-rc3 custom kernel";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let 
      pkgs = import nixpkgs { system = "x86_64-linux"; };

      # Debianの最小ルートFSイメージを取得
      debianImage = pkgs.fetchurl {
        url = "https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2";
        sha256 = "d79f7038039df0b0768ff583385f09eb117395327c2b5d541b29e23582bd595c";
      };

      # カスタムカーネルのビルド定義
      myKernel = pkgs.linuxManualConfig {
        # カーネルバージョンとモジュールディレクトリ名
        version = "6.16-rc3";
        modDirVersion = "6.16-rc3";

        # ソースコードはflakeのルート (カレントディレクトリ) を使用
        src = ./.;
        # あらかじめ用意したカーネル設定ファイルを指定 (例: リポジトリ直下にlinux-configがあると仮定)
        configfile = ./linux-config;
        allowImportFromDerivation = true;

        # 追加で有効にする設定 (デバッグ関連や必須ドライバを組込み)
        extraConfig = ''
          DEBUG_KERNEL y
          DEBUG_INFO y        # デバッグシンボルを有効化
          GDB_SCRIPTS y       # GDBヘルパースクリプトを有効化
          FRAME_POINTER y     # フレームポインタを有効化
          # 仮想デバイス/ファイルシステムをカーネルに組み込む (initrd無しでブートするため)
          VIRTIO_PCI y
          VIRTIO_BLK y
          VIRTIO_NET y
          SERIAL_8250 y
          SERIAL_8250_CONSOLE y
          EXT4_FS y
          EXT4_FS_POSIX_ACL y
          EXT4_FS_SECURITY y
        '';
        ignoreConfigErrors = true;  # 一部のextraConfig項目で不整合があってもビルド継続
      };

      # QEMUでカーネルを起動するスクリプト (nix run用)
      runQemu = pkgs.writeShellScriptBin "run-qemu" ''
        #!/bin/sh
        # QEMUでカーネルを起動 (GDBスタブ有効, シリアルコンソールを使用)
        exec ${pkgs.qemu}/bin/qemu-system-x86_64 -m 1024 -nographic \
             -kernel ${myKernel}/bzImage \
             -append "console=ttyS0 root=/dev/vda nokaslr" \
             -drive file=${debianImage},if=virtio,format=qcow2 \
             -s -S  # GDBスタブ有効(-s)＆起動停止(-S)
      '';

    in {
      # ビルドできるパッケージとしてカーネルをエクスポート
      packages.x86_64-linux.kernel = myKernel;
      # `nix run`で実行可能なアプリケーションとしてQEMU起動スクリプトをエクスポート
      apps.x86_64-linux.default = runQemu;
      # 開発用シェル: QEMUやビルドツール、GDB等を含む環境
      devShell.x86_64-linux = pkgs.mkShell {
        packages = with pkgs; [
          qemu gcc ccache gdb git
          bc bison flex pkgconfig ncurses cscope   # カーネルビルド・開発に必要なツール
        ];
      };
    };
}
