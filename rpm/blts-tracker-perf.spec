Name:       blts-tracker-perf

Summary:    BLTS tracker performance test suite
Version:    0.0.1
Release:    0
Group:      Development/Testing
License:    GPLv2
URL:        https://github.com/mer-qa/blts-tracker-perf
Source0:    %{name}-%{version}.tar.gz
Requires:   dbus-x11
Requires:   tracker
Requires:   tracker-tests

%description
This package contains tracker performance tests


%prep
%setup -q -n %{name}-%{version}

%build

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}/opt/tests/blts-tracker-perf
install --mode=644 common.sh %{buildroot}/opt/tests/blts-tracker-perf
install --mode=755 test-indexing.sh %{buildroot}/opt/tests/blts-tracker-perf
install --mode=644 test-storage-io.cnf %{buildroot}/opt/tests/blts-tracker-perf
install --mode=755 test-storage-io.sh %{buildroot}/opt/tests/blts-tracker-perf
install --mode=644 tests.xml %{buildroot}/opt/tests/blts-tracker-perf

%files
%defattr(-,root,root,-)
/opt/tests/blts-tracker-perf/*
