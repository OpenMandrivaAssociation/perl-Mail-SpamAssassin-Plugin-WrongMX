Summary:	The WrongMX Plugin for SpamAssassin
Name:		perl-Mail-SpamAssassin-Plugin-WrongMX
Version:	0
Release:	7
License:	Apache License
Group:		Development/Perl
URL:		https://people.apache.org/~dos/sa-plugins/3.0/
Source0:	http://people.apache.org/~dos/sa-plugins/3.0/wrongmx.cf
Source1:	http://people.apache.org/~dos/sa-plugins/3.0/wrongmx.pm
Requires(pre): rpm-helper
Requires(postun): rpm-helper
Requires(pre):  spamassassin-spamd >= 3.1.1
Requires:	spamassassin-spamd >= 3.1.1
BuildArch:	noarch
BuildRoot:	%{_tmppath}/%{name}-%{version}-%{release}-buildroot

%description
WrongMX determines if an email was sent to a lower preference MX when a higher
preference MX was likely available.

 o How To Use It:
   Save the two files above in your local configuration directory 
   (/etc/mail/spamassassin/) and set the score in wrongmx.cf to whatever you
   desire, based on your confidence in your primary MX server stability.

  o How NOT To Use It:
    Do not use this plugin on overloaded mail systems that frequently stop
    accepting connections on the primary MX servers due to system load since
    it will cause some false positives if you set the score too high.

%prep

%setup -q -T -c -n %{name}-%{version}

cp %{SOURCE0} WrongMX.cf
cp %{SOURCE1} WrongMX.pm

# fix package name and path
perl -pi -e "s|WrongMX wrongmx\.pm|Mail::SpamAssassin::Plugin::WrongMX %{perl_vendorlib}/Mail/SpamAssassin/Plugin/WrongMX.pm|g" WrongMX.cf
perl -pi -e "s|^package WrongMX|package Mail::SpamAssassin::Plugin::WrongMX|g" WrongMX.pm

%build

%install
[ "%{buildroot}" != "/" ] && rm -rf %{buildroot}

install -d %{buildroot}%{_sysconfdir}/mail/spamassassin/
install -d %{buildroot}%{perl_vendorlib}/Mail/SpamAssassin/Plugin

install -m0644 WrongMX.cf %{buildroot}%{_sysconfdir}/mail/spamassassin/
install -m0644 WrongMX.pm %{buildroot}%{perl_vendorlib}/Mail/SpamAssassin/Plugin/

%post
if [ -f %{_var}/lock/subsys/spamd ]; then
    %{_initrddir}/spamd restart 1>&2;
fi
    
%postun
if [ "$1" = "0" ]; then
    if [ -f %{_var}/lock/subsys/spamd ]; then
        %{_initrddir}/spamd restart 1>&2
    fi
fi

%clean
[ "%{buildroot}" != "/" ] && rm -rf %{buildroot}

%files
%defattr(644,root,root,755)
%attr(0644,root,root) %config(noreplace) %{_sysconfdir}/mail/spamassassin/WrongMX.cf
%{perl_vendorlib}/Mail/SpamAssassin/Plugin/WrongMX.pm


%changelog
* Fri Sep 04 2009 Thierry Vignaud <tv@mandriva.org> 0-5mdv2010.0
+ Revision: 430497
- rebuild

* Sun Jul 20 2008 Oden Eriksson <oeriksson@mandriva.com> 0-4mdv2009.0
+ Revision: 239112
- rebuild

  + Olivier Blin <oblin@mandriva.com>
    - restore BuildRoot

  + Thierry Vignaud <tv@mandriva.org>
    - kill re-definition of %%buildroot on Pixel's request

* Sun Jul 01 2007 Oden Eriksson <oeriksson@mandriva.com> 0-3mdv2008.0
+ Revision: 46379
- misc fixes


* Sat Nov 25 2006 Emmanuel Andry <eandry@mandriva.org> 0-2mdv2007.0
+ Revision: 87294
- patch to fix perl module path
- Import perl-Mail-SpamAssassin-Plugin-WrongMX

