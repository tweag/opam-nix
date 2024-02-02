pkgs:
with pkgs;
# Map from debian package names to nixpkgs packages.
# To add a new package:
# 1. Find the package in nixpkgs:
#   * Use https://search.nixos.org/packages or `nix search` to find the package by name or description;
#   * Use https://mynixos.com/ or `nix-index`/`nix-locate` to find the package by files contained therein;
# 2. If some changes to the package are needed to be compatible with the debian one, make an override in the let binding below;
# 3. Add it to the list. Keep the quotation marks around the debian package name, even if not needed, and sort the list afterwrads.
let
  inherit (lib) warn;

  notPackaged = name:
    warn ''
      [opam-nix] ${name} is not packaged in nixpkgs, or at least was not packaged at the time this was written.
      Check https://github.com/NixOS/nixpkgs/pulls?q=${name} to see if it has been added in the meantime.
      If it has, please update <opam-nix>/src/external/debian.nix;
      If it hasn't, your best bet is to package it yourself and then add to buildInputs of your package directly.
    '' null;

  hidapi' = hidapi.overrideAttrs (_: {
    postInstall = ''
      mv $out/include/hidapi/* $out/include
      rm -d $out/include/hidapi
      ln -s $out/lib/libhidapi-hidraw.la $out/lib/libhidapi.la
      ln -s $out/lib/libhidapi-hidraw.so.0.0.0 $out/lib/libhidapi.so
    '';
  });

  cargo' = buildEnv {
    name = "cargo";
    paths = [ pkgsBuildBuild.cargo pkgsBuildHost.rustc ];
  };

  gtksourceview' = buildEnv {
    name = "gtk-bunch";
    paths = [
      gnome2.gtksourceview
      gnome2.gtk.dev
      pango.dev
      glib.dev
      harfbuzz.dev
      cairo.dev
      gdk-pixbuf.dev
      atk.dev
      freetype.dev
      fontconfig.dev
    ];
  };

  curl-gnutls = curl.override { gnutlsSupport = true; opensslSupport = false; };

  xorg-dev = buildEnv {
    name = "xorg-combined";
    ignoreCollisions = true;
    paths = with xorg; [
      libdmx
      libfontenc
      libICE.dev
      libSM.dev
      libX11.dev
      libXau.dev
      libXaw.dev
      libXcomposite.dev
      libXcursor.dev
      libXdamage.dev
      libXdmcp.dev
      libXext.dev
      libXfixes.dev
      libXfont.dev
      libXft.dev
      libXi.dev
      libXinerama.dev
      libxkbfile.dev
      libXmu.dev
      libXpm.dev
      libXrandr.dev
      libXrender.dev
      libXres.dev
      libXScrnSaver
      libXt.dev
      libXtst
      libXv.dev
      libXvMC.dev
      xorgserver.dev
      xtrans
      xorgproto
    ];
  };

  withSdl2 = otherLib: buildEnv {
    name = "${otherLib.name}-combined";
    paths = [
      otherLib
      SDL2.dev
    ];
  };

  # Please keep this list sorted alphabetically and one-line-per-package
in pkgs // {
  "adwaita-icon-theme" = gnome.adwaita-icon-theme;
  "autoconf" = pkgsBuildBuild.autoconf;
  "binutils-multiarch" = binutils;
  "cargo" = cargo';
  "coinor-csdp" = csdp;
  "debianutils" = which; # eurgh
  "default-jdk" = openjdk;
  "freeglut3-dev" = freeglut.dev;
  "freetds-dev" = freetds;
  "frei0r-plugins-dev" = frei0r;
  "g++" = pkgsBuildHost.gcc;
  "gnuplot-x11" = gnuplot;
  "guile-3.0-dev" = guile_3_0.dev;
  "hdf4-tools" = hdf4;
  "jq" = pkgsBuildBuild.jq;
  "libaio-dev" = libaio;
  "libao-dev" = libao.dev;
  "libargon2-0" = libargon2;
  "libasound2-dev" = alsa-lib.dev;
  "libassimp-dev" = assimp.dev;
  "libaugeas-dev" = augeas;
  "libavcodec-dev" = ffmpeg.dev;
  "libavdevice-dev" = ffmpeg.dev;
  "libavfilter-dev" = ffmpeg.dev;
  "libavformat-dev" = ffmpeg.dev;
  "libavutil-dev" = ffmpeg.dev;
  "libbdd-dev" = buddy;
  "libblas-dev" = blas.dev;
  "libbluetooth-dev" = bluez5;
  "libboost-dev" = boost.dev;
  "libbrotli-dev" = brotli.dev;
  "libbz2-dev" = bzip2.dev;
  "libc6-dev" = glibc.dev;
  "libcairo2-dev" = cairo.dev;
  "libcapnp-dev" = capnproto;
  "libcurl4-gnutls-dev" = curl-gnutls.dev;
  "libdw-dev" = elfutils.dev;
  "libev-dev" = libev;
  "libevent-dev" = libevent.dev;
  "libexpat1-dev" = expat.dev;
  "libfaad-dev" = faad2;
  "libfarmhash-dev" = notPackaged "libfarmhash";
  "libfdk-aac-dev" = fdk_aac;
  "libffi-dev" = libffi.dev;
  "libfftw3-dev" = fftw.dev;
  "libflac-dev" = flac.dev;
  "libfontconfig1-dev" = fontconfig.dev;
  "libfreetype6-dev" = freetype.dev;
  "libfswatch-dev" = fswatch;
  "libftgl-dev" = ftgl;
  "libfuse-dev" = fuse;
  "libgammu-dev" = gammu;
  "libgavl-dev" = notPackaged "libgavl";
  "libgc-dev" = boehmgc.dev;
  "libgd-dev" = gd.dev;
  "libgdbm-dev" = gdbm;
  "libgeoip-dev" = geoip;
  "libgif-dev" = giflib;
  "libgirepository1.0-dev" = gobject-introspection.dev;
  "libgl1-mesa-dev" = libGL.dev;
  "libglade2-dev" = glade;
  "libgles2-mesa-dev" = libGL.dev;
  "libglew-dev" = glew.dev;
  "libglfw3-dev" = glfw3;
  "libglib2.0-dev" = glib.dev;
  "libglpk-dev" = glpk;
  "libglu1-mesa-dev" = libGL.dev;
  "libgmp-dev" = gmp.dev;
  "libgnomecanvas2-dev" = gnome2.libgnomecanvas.dev;
  "libgnutls28-dev" = gnutls.dev;
  "libgoocanvas-2.0-dev" = goocanvas2.dev;
  "libgoogle-perftools-dev" = gperftools;
  "libgrib-api-dev" = grib-api;
  "libgsasl7-dev" = gsasl;
  "libgsl-dev" = gsl;
  "libgstreamer-plugins-base1.0-dev" = gst_all_1.gst-plugins-base.dev;
  "libgstreamer1.0-dev" = gst_all_1.gstreamer.dev;
  "libgtk-3-dev" = gtk3.dev;
  "libgtk2.0-dev" = gtk2.dev;
  "libgtksourceview-3.0-dev" = gtksourceview3.dev;
  "libgtksourceview2.0-dev" = gtksourceview';
  "libgtkspell3-3-dev" = gtkspell3;
  "libhdf4-dev" = hdf4.dev;
  "libhdf5-dev" = hdf5.dev;
  "libhidapi-dev" = hidapi';
  "libipc-system-simple-perl" = perlPackages.IPCSystemSimple;
  "libirrlicht-dev" = irrlicht;
  "libjack-dev" = jack1;
  "libjack-jackd2-dev" = jack2;
  "libjavascriptcoregtk-3.0-dev" = webkitgtk.dev;
  "libjemalloc-dev" = jemalloc;
  "libjpeg-dev" = libjpeg.dev;
  "libkrb5-dev" = krb5.dev;
  "libkyotocabinet-dev" = kyotocabinet;
  "liblapack-dev" = lapack.dev;
  "liblapacke-dev" = lapack.dev;
  "libleveldb-dev" = leveldb.dev;
  "liblilv-dev" = lilv.dev;
  "liblinear-tools" = liblinear.bin;
  "liblldb-3.5-dev" = lldb.dev;
  "liblmdb-dev" = lmdb.dev;
  "liblo-dev" = liblo;
  "liblua5.2-dev" = lua5_2;
  "liblz4-dev" = lz4.dev;
  "liblz4-tool" = lz4.bin;
  "liblzma-dev" = lzma.dev;
  "liblzo2-dev" = lzo;
  "libmad0-dev" = libmad;
  "libmagic-dev" = file;
  "libmagickcore-dev" = imagemagick.dev;
  "libmariadb-dev" = mariadb;
  "libmaxminddb-dev" = libmaxminddb;
  "libmbedtls-dev" = mbedtls;
  "libmecab-dev" = mecab;
  "libmilter-dev" = libmilter;
  "libmosquitto-dev" = mosquitto;
  "libmp3lame-dev" = lame;
  "libmpfr-dev" = mpfr.dev;
  "libmpg123-dev" = mpg123;
  "libnanomsg-dev" = nanomsg;
  "libnauty2-dev" = nauty.dev;
  "libnl-3-dev" = libnl;
  "libnl-route-3-dev" = libnl;
  "libnlopt-dev" = nlopt;
  "libode-dev" = ode;
  "libogg-dev" = libogg.dev;
  "libonig-dev" = oniguruma;
  "libopenbabel-dev" = openbabel;
  "libopenblas-dev" = openblas.dev;
  "libopencc1.1" = opencc;
  "libopencc1" = opencc;
  "libopencc2" = opencc;
  "libopenimageio-dev" = openimageio.dev;
  "libopenjpeg" = openjpeg.dev;
  "libopus-dev" = libopus.dev;
  "libpango1.0-dev" = pango.dev;
  "libpapi-dev" = papi;
  "libpcre2-dev" = pcre2.dev;
  "libpcre3-dev" = pcre.dev;
  "libplplot-dev" = plplot;
  "libpng-dev" = libpng.dev;
  "libportmidi-dev" = portmidi;
  "libppl-dev" = ppl;
  "libpq-dev" = postgresql;
  "libproj-dev" = proj.dev;
  "libprotobuf-dev" = protobuf;
  "libprotoc-dev" = protobuf;
  "libpulse-dev" = pulseaudio.dev;
  "libqrencode-dev" = qrencode.dev;
  "libqt4-dev" = qt4.dev;
  "librdkafka-dev" = rdkafka;
  "librocksdb-dev" = rocksdb;
  "librsvg2-dev" = librsvg.dev;
  "libsamplerate0-dev" = libsamplerate.dev;
  "libschroedinger-dev" = schroedinger.dev;
  "libsdl-gfx1.2-dev" = SDL_gfx;
  "libsdl-image1.2-dev" = SDL_image;
  "libsdl-mixer1.2-dev" = SDL_mixer;
  "libsdl-net1.2-dev" = SDL_net;
  "libsdl-ttf2.0-dev" = SDL_ttf;
  "libsdl1.2-dev" = SDL.dev;
  "libsdl2-dev" = SDL2.dev;
  "libsdl2-image-dev" = withSdl2 SDL2_image;
  "libsdl2-mixer-dev" = withSdl2 SDL2_mixer.dev;
  "libsdl2-net-dev" = withSdl2 SDL2_net;
  "libsdl2-ttf-dev" = withSdl2 SDL2_ttf;
  "libseccomp-dev" = libseccomp.dev;
  "libsecp256k1-0" = secp256k1;
  "libsecp256k1-dev" = secp256k1;
  "libsfml-dev" = sfml;
  "libshine-dev" = shine;
  "libshp-dev" = shapelib;
  "libsnappy-dev" = snappy.dev;
  "libsodium-dev" = libsodium.dev;
  "libsoundtouch-dev" = soundtouch;
  "libsource-highlight-dev" = sourceHighlight.dev;
  "libspeex-dev" = speex.dev;
  "libspf2-dev" = libspf2;
  "libsqlite3-dev" = sqlite.dev;
  "libsrt-gnutls-dev" = warn "[opam-nix] warning: srt in nixpkgs does not support gnutls" srt;
  "libsrt-openssl-dev" = srt;
  "libssh-dev" = libssh;
  "libssl-dev" = openssl.dev;
  "libstring-shellquote-perl" = perlPackages.StringShellQuote;
  "libsvm-dev" = libsvm;
  "libsvm-tools" = libsvm;
  "libswresample-dev" = ffmpeg.dev;
  "libswscale-dev" = ffmpeg.dev;
  "libsystemd-dev" = systemd.dev;
  "libtag1-dev" = taglib;
  "libtheora-dev" = libtheora.dev;
  "libtidy-dev" = libtidy;
  "libtraildb-dev" = notPackaged "traildb";
  "libudunits2-dev" = udunits;
  "libusb-1.0-0-dev" = libusb1.dev;
  "libuv1-dev" = libuv;
  "libvirt-dev" = libvirt;
  "libvo-aacenc-dev" = vo-aacenc;
  "libvorbis-dev" = libvorbis.dev;
  "libwxgtk-media3.0-dev" = wxGTK30;
  "libwxgtk-webview3.0-dev" = wxGTK30;
  "libwxgtk3.0-dev" = wxGTK30;
  "libx11-dev" = xorg.libX11.dev;
  "libxcb-image0-dev" = xorg.libxcb.dev;
  "libxcb-keysyms1-dev" = xorg.libxcb.dev;
  "libxcb-shm0-dev" = xorg.libxcb.dev;
  "libxcb-xkb-dev" = xorg.libxcb.dev;
  "libxcb1-dev" = xorg.libxcb.dev;
  "libxcursor-dev" = xorg-dev;
  "libxen-dev" = xen;
  "libxi-dev" = xorg.libXi.dev;
  "libxinerama-dev" = xorg-dev;
  "libxkbcommon-dev" = libxkbcommon.dev;
  "libxrandr-dev" = xorg.libXrandr.dev;
  "libxxhash-dev" = xxHash;
  "libyara-dev" = yara;
  "libzbar-dev" = zbar.dev;
  "libzmq3-dev" = zeromq4;
  "libzstd-dev" = zstd.dev;
  "ligonig-dev" = oniguruma;
  "linux-libc-dev" = glibc.dev;
  "llvm-14-dev" = llvm_14.dev;
  "llvm-9-dev" = llvm_9.dev;
  "llvm-dev" = llvm.dev;
  "m4" = pkgsBuildBuild.m4;
  "mesa-common-dev" = mesa.dev;
  "mpi-default-dev" = mpi;
  "ncurses-dev" = ncurses.dev;
  "neko-dev" = neko;
  "neko" = neko;
  "nettle-dev" = nettle.dev;
  "npm" = nodePackages.npm;
  "perl" = pkgsBuildBuild.perl;
  "pkg-config" = pkgsBuildBuild.pkg-config;
  "portaudio19-dev" = portaudio;
  "postgresql-common" = postgresql;
  "protobuf-compiler" = protobufc;
  "python2.7-dev" = python27;
  "python2.7" = python27;
  "python3-dev" = python3;
  "python3-distutils" = python3.pkgs.distutils_extra;
  "python3-yaml" = python3.pkgs.pyyaml;
  "qt4-qmake" = qt4;
  "qt5-qmake" = qt5.qmake;
  "qtdeclarative5-dev" = qt5.qtdeclarative.dev;
  "r-base-core" = R;
  "r-mathlib" = R;
  "ruby-sass" = sass;
  "sdpa" = notPackaged "sdpa";
  "swi-prolog" = swiProlog;
  "tcl-dev" = tcl;
  "tcl8.5-dev" = tcl-8_5;
  "texlive-latex-base" = texlive.combined.scheme-basic;
  "thrift-compiler" = thrift;
  "tk-dev" = tk.dev;
  "tk8.5-dev" = tk-8_5.dev;
  "unixodbc-dev" = unixODBC;
  "uuid-dev" = libuuid.dev;
  "vim-nox" = vim;
  "wx3.0-headers" = wxGTK30;
  "xorg-dev" = xorg-dev;
  "xvfb" = xvfb-run;
  "zlib1g-dev" = zlib.dev;
}
