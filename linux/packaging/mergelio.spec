# RPM spec for Mergelio.
#
# Not built by hand — scripts/build-linux-rpm.sh stages the Flutter bundle and
# passes the values below with --define. There is no %prep or %build stage:
# the payload is an already compiled bundle, so %install only copies the
# staged tree into the buildroot.
#
#   rpmbuild -bb --define "_topdir <tmp>" --define "app_version 1.4.0" \
#            --define "stagedir <tree>" linux/packaging/mergelio.spec

# The bundle ships prebuilt binaries. Leave them alone: the default post-install
# pass would strip them and try to split out debug symbols that do not exist.
%global debug_package %{nil}
%global __os_install_post %{nil}
%global _build_id_links none

# The bundled Flutter libraries under /opt are private to this app. Both halves
# of the automatic dependency machinery have to be switched off for them, and
# leaving either one on breaks the package:
#
#   - provides: without this the package advertises libflutter_linux_gtk.so and
#     friends as system-wide providers, which they are not.
#   - requires: the executable links against those same private libraries, so
#     rpm would demand sonames that nothing in the distribution provides and
#     dnf would refuse to install.
#
# Filtering requires for the whole directory also drops the genuine system
# dependencies rpm would have derived, so those are listed by hand below.
%global __provides_exclude_from ^/opt/%{name}/.*$
%global __requires_exclude_from ^/opt/%{name}/.*$

%define app_id com.mergelio.mergelio

Name:           mergelio
Version:        %{app_version}
Release:        1%{?dist}
Summary:        Free, cross-platform visual Git client

License:        BSD-3-Clause
URL:            https://github.com/senseyman/mergelio

# Automatic dependency generation is off for everything this package ships, so
# every runtime dependency is spelled out. glibc is deliberately absent: it is
# guaranteed to be present and pinning it would only narrow the package.
Requires:       gtk3
Requires:       glib2
Requires:       libstdc++
Requires:       zlib
Requires:       git

%description
Mergelio is a desktop Git client with a commit graph, staging, diffs,
merge and rebase tooling, and worktree support.

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}
cp -a %{stagedir}/. %{buildroot}/

%files
%license %{_datadir}/licenses/%{name}/LICENSE
/opt/%{name}/
%{_bindir}/%{name}
%{_datadir}/applications/%{app_id}.desktop
%{_datadir}/icons/hicolor/256x256/apps/%{app_id}.png

# Without these the entry and icon exist on disk but the shell keeps showing a
# stale menu and a generic icon until the next login.
%post
update-desktop-database -q %{_datadir}/applications &>/dev/null || :
gtk-update-icon-cache -q -f %{_datadir}/icons/hicolor &>/dev/null || :

%postun
update-desktop-database -q %{_datadir}/applications &>/dev/null || :
gtk-update-icon-cache -q -f %{_datadir}/icons/hicolor &>/dev/null || :

%changelog
# Release notes live in the GitHub release, not here.
