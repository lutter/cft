%{!?ruby_sitelibdir: %define ruby_sitelibdir %(ruby -rrbconfig -e 'puts Config::CONFIG["sitelibdir"]')}

%define has_ruby_abi 0%{?fedora:%fedora} >= 5 || 0%{?rhel:%rhel} >= 5
%define has_ruby_noarch %has_ruby_abi

Summary: Config file tracker
Name: cft

Version: 0.2.2
Release: 1%{?dist}
Group: System Environment/Base
License: GPL
URL: http://cft.et.redhat.com/
Source: http://cft.et.redhat.com/download/cft-%{version}.tgz
BuildRoot: %{_tmppath}/%{name}-%{version}-%{release}-root-%(%{__id_u} -n)
Requires: ruby
%if %has_ruby_abi
Requires: ruby(abi) = 1.8
%endif
Requires: puppet >= 0.24.0
Requires: ruby-fam
Requires: ruby-rpm >= 1.2.3
BuildRequires: ruby 
%if %has_ruby_noarch
BuildArch: noarch
%endif
Provides: ruby(cft) = %{version}

%description
Cft (pronounced 'sift') follows a sysadmin as she makes changes to the
system, records the changes and produces a puppet manifest from them.  Its
basic workings are inspired by Gnome's Sabayon, a tool that watches a user
make configuration changes to their desktop and collects them into a
reusable bundle. Instead of the desktop though, cft is focused on
traditional system admins and how they maintain machines, mostly with
command line tools. Cft uses puppet as its backbone for expressing the
configuration of a system, and for understanding in greater detail what
changes the admin has made to the system.

%prep
%setup -q

%build

%install
rm -rf %{buildroot}
install -d -m0755 %{buildroot}%{_sbindir}
install -d -m0755 %{buildroot}%{ruby_sitelibdir}

install -p -m0755 bin/cft %{buildroot}%{_sbindir}
cp -pr lib/* %{buildroot}%{ruby_sitelibdir}

%clean
%{__rm} -rf %{buildroot}

%files
%defattr(-, root, root)
%doc AUTHORS COPYING INSTALL README TODO NEWS
%{_sbindir}/cft
%{ruby_sitelibdir}/cft.rb
%{ruby_sitelibdir}/cft

%changelog
* Mon Dec 17 2007 David Lutterkort <dlutter@redhat.com> - 0.2.2-1
- New version

* Mon May  7 2007 David Lutterkort <dlutter@redhat.com> - 0.2.1-1
- New version

* Wed Mar 21 2007 David Lutterkort <dlutter@redhat.com> - 0.2.0-1
- New version

* Tue Mar 13 2007 David Lutterkort <dlutter@redhat.com> - 0.1.0-3
- Fix ruby(abi) dependency so that it builds on RHEL4

* Thu Jan 25 2007 David Lutterkort <dlutter@redhat.com> - 0.1.0-2
- Fix typo in prep

* Mon Jan  8 2007 David Lutterkort <dlutter@redhat.com> - 0.0.1-1
- Initial specfile

