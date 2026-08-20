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

# The bundled Flutter libraries under /opt are private to this app. Without
# this the package would advertise them as system-wide providers.
%global __provides_exclude_from ^/opt/%{name}/.*$

%define app_id com.mergelio.mergelio

Name:           mergelio
Version:        %{app_version}
Release:        1%{?dist}
Summary:        Free, cross-platform visual Git client

License:        BSD-3-Clause
URL:            https://github.com/senseyman/mergelio

# rpm derives the library dependencies from the binaries it packages, so only
# what it cannot see is listed here: gtk3 as the toolkit behind those sonames,
# and git, which the app runs as a subprocess.
Requires:       gtk3
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
