{ lib
, stdenv
, fetchurl
, meson
, ninja
, pkg-config
, gobject-introspection
, glib
, gtk3
, libxklavier
, wrapGAppsHook
, gnome
}:

stdenv.mkDerivation rec {
  pname = "libgnomekbd";
  version = "3.28.0";

  outputs = [ "out" "dev" ];

  src = fetchurl {
    url = "mirror://gnome/sources/${pname}/${lib.versions.majorMinor version}/${pname}-${version}.tar.xz";
    sha256 = "swV6RD5MJvkf41Lc0RVKVs3VHxz9fLas4wDDzBKGWck=";
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    wrapGAppsHook
    glib
    gobject-introspection
  ];

  # Requires in libgnomekbd.pc
  propagatedBuildInputs = [
    gtk3
    libxklavier
    glib
  ];

  postInstall = ''
    # Missing post-install script.
    glib-compile-schemas "$out/share/glib-2.0/schemas"
  '';

  passthru = {
    updateScript = gnome.updateScript {
      packageName = pname;
      versionPolicy = "odd-unstable";
    };
  };

  meta = with lib; {
    description = "Keyboard management library";
    maintainers = teams.gnome.members;
    license = licenses.gpl2;
    platforms = platforms.linux;
  };
}
