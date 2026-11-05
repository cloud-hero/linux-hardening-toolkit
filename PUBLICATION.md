# LH-1.5 release

This release adds a six-step copy-and-paste workflow and observational collection for Ubuntu 24.04, Debian 13, Fedora 44 and Amazon Linux 2023. Fixed control catalogue LH-1.2 is unchanged.

The collection scripts select distribution-appropriate commands, retain missing observations, distinguish DNF exit 100 from execution failures and use private scratch copies for RPM metadata queries. No repository refresh or package installation occurs during assessment. The default baseline scope now includes RPM-family configuration paths; baseline creation still requires separate approval.

Disposable EC2 collection, private capture, SCP integrity, missing-cache handling and before/after state checks were performed on 5 November 2026. See ec2-validation.md and its machine-readable summary. Historical Ubuntu hardening tests remain separate. The retained PDF is explicitly the original LH-1.4 edition; the new workflow lives in quickstart.md and linux-server-hardening-guide.md.

Root tools and scripts copies must match. SHA256SUMS records the reviewed release files. Validate the package before publishing; the fixed catalogue remains LH-1.2. Website publication is a separate deployment after the versioned tag and downloads are available.
