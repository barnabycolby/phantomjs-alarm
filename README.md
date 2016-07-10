This script downloads ARM builds of PhantomJS from the Arch Linux ARM servers and packages them to look like the official PhantomJS download archives. It can also be used to package standalone binaries.

# Why?
ARM builds of PhantomJS are not officially supported by the PhantomJS team, and building them requires a lot of time/hardware. To solve this problem, the script piggy backs on the work of the Arch Linux ARM build servers, who already compile them for us.

# Where can I find the ARM archives built by this script?
https://phantomjs.barnabycolby.io

# Can I use a different package mirror?
An alternate arch package archive can be specified by passing in the URL as a parameter to the script. This is useful for downloading older packages no longer hosted by the official ALARM package mirrors.

```bash
sh phantomjsdownload.sh "http://tardis.tiny-vps.com/aarm/packages/p/phantomjs/"
```

# Can I package standalone binaries?
If you have a PhantomJS binary, you can ask the script to package it for you by passing in the path to the binary, its version number and its target architecture.

```bash
sh phantomjsdownload.sh <path to binary> 1.9.8 armv7h
```
