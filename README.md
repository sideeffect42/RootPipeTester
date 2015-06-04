![RootPipe Tester - because for more than 10 years nobody cared](docs/img/readme-header.png)

### Table of Contents
1. [What is RootPipe Tester?](#1-what-is-rootpipe-tester)
2. [Why should I use RootPipe Tester?](#2-why-should-i-use-rootpipe-tester)
3. [How do I use RootPipe Tester?](#3-how-do-i-use-rootpipe-tester)
4. [PANIC!!! My system is vulnerable? Are we all going to die?](#4-panic-my-system-is-vulnerable-are-we-all-going-to-die)
	1. [OS X 10.10 (Yosemite)](#41-os-x-1010-yosemite)
	2. [OS X 10.9 (Mavericks)](#42-os-x-109-mavericks)
	3. [OS X 10.8 (Mountain Lion)](#43-os-x-108-mountain-lion)
	4. [OS X 10.7 (Lion), Mac OS X 10.6 (Snow Leopard), Mac OS X 10.5 (Leopard), Mac OS X 10.4 (Tiger)](#44-os-x-107-lion-mac-os-x-106-snow-leopard-mac-os-x-105-leopard-mac-os-x-104-tiger)
	5. [Mac OS X 10.3 (Panther)](#45-mac-os-x-103-panther)
	6. [Mac OS X 10.2 (Jaguar)](#46-mac-os-x-102-jaguar)
	7. [Mac OS X 10.1 (Puma), Mac OS X 10.0 (Cheetah)](#47-mac-os-x-101-puma-mac-os-x-100-cheetah)
5. [About RootPipe](#5-about-rootpipe)
	1. [How does RootPipe work?](#51-how-does-rootpipe-work)
	2. [Is it a backdoor?](#52-is-it-a-backdoor)

## 1. What is RootPipe Tester?
RootPipe Tester is a small application that runs on your Mac (Mac OS X 10.2.8 or higher, both PowerPC and Intel) and tries to use the RootPipe Exploit ([CVE-2015-1130](http://www.cvedetails.com/cve/CVE-2015-1130/)) to produce a privilege escalation.

## 2. Why should I use RootPipe Tester?
### Can't you just make a list of vulnerable Mac OS versions?
If your Mac is vulnerable does depend on the version of Mac OS X you are running but its success is also dependent on the preferences you have set.  
With RootPipe Tester I have created a one-click solution for you to verify if you are vulnerable without having to do extensive testing and trying.

## 3. How do I use RootPipe Tester?
Download the disk image from the releases page of this repository or compile it by your own if you prefer.  
Mount the disk image and run the application contained within it (it is safe to run RootPipe Tester from the disk image).  
Click "Start Test" and let the test run through (you can tell if it's finished by the "Running…" in the window title).

To get accurate results I recommend rebooting your Mac and running the test again on a "fresh login".

If at least one of the test runs detected a vulnerable system you might want to check out the PANIC section.

## 4. PANIC!!! My system is vulnerable? Are we all going to die?
No! Keep calm and read the guide appropriate to your system version.

Note: Not vulnerable in user authorization means that the system will either not grant access or pop up an authorization dialog which prompts you to authenticate as an Administrator user.  
To some extent this is also a privilege escalation, because the admin group doesn't have as many rights as root, but in the default configuration of `sudo`, every user in the group "admin" can get root by entering his password, so the same effect can also be achieved by simply running `sudo`.


### 4.1. OS X 10.10 (Yosemite)
Upgrade to 10.10.3 as soon as possible to make sure the system enforces entitlements on the `writeconfig` binary correctly. (at least that's what Apple says)

If for some reason you cannot upgrade to 10.10.3, check the section for OS X 10.9 Mavericks.

### 4.2. OS X 10.9 (Mavericks)
Mavericks let's an exploiter get through with nil authorization so you're in a much more difficult situation than with older versions of Mac OS X.  


You may want to have a look at [can\_I\_suid](https://github.com/gdbinit/can_I_suid).

Test results:

#### nil authorization:  
Vulnerable  
#### user authorization:  
- __Administrator account__: Vulnerable only if “Require password to unlock each System Preferences pane” is not checked.  
- __Standard user account__: Not vulnerable


### 4.3. OS X 10.8 (Mountain Lion)
You should enable "Require password to unlock each System Preferences pane" in the Security preference pane.

Test results:

#### nil authorization:  
Not vulnerable  
#### user authorization:  
- __Administrator account__: Vulnerable only if “Require password to unlock each System Preferences pane” is not checked.  
- __Standard user account__: Not vulnerable


### 4.4. OS X 10.7 (Lion), Mac OS X 10.6 (Snow Leopard), Mac OS X 10.5 (Leopard), Mac OS X 10.4 (Tiger)
Congratulations! You have one of the most secure versions of Mac OS X (at least as far as RootPipe is concerned).

On these systems, the "Require password to unlock each System Preference pane" ("Require password to unlock each secure system preference" in Tiger) in the Security preference pane is working properly and _should really be enabled_!

Note: If the "Require password" checkbox is unchecked, the system will unlock secure preference panes on _each_ login. If you're using an Administrator account this will make your system vulnerable until you have manually closed the lock in the System Preferences after each login.

Test results:

#### nil authorization:  
Not vulnerable  
#### user authorization:  
- __Administrator account__: Vulnerable only if _both_ "Require password" is unchecked and secure preference panes are unlocked.  
Attention: If "Require password" is unchecked, the system will unlock secure preference panes on _each_ login.  
- __Standard user account__: Not vulnerable


### 4.5. Mac OS X 10.3 (Panther)
Unlike on later systems, in Panther, the "Require password to unlock each secure system preference" checkbox in the Security preference pane does not have the effect of fully hindering this exploit from working. I still recommend checking it.  
To secure your system I _strongly_ recommend to switch to using a standard user account only and always manually "closing the lock" after changing preferences in System Preferences.  
Only closing System Preferences will not properly invalidate the authorization and this exploit will work until you log out although the System Preferences GUI shows a closed lock as a Standard user.

Test results:

#### nil authorization:  
Not vulnerable  
#### user authorization:  
- __Administrator account__: Vulnerable if secure preference panes are unlocked or have not been manually locked (by opening, if needed, and closing the lock in System Preferences) after login.  
- __Standard user account__: Vulnerable if secure preference panes are unlocked.


### 4.6. Mac OS X 10.2 (Jaguar)
Unlike later systems, Jaguar does not provide a "Require password to unlock each secure system preference" checkbox but still unlocks secure preference panes at login for all Administrator users.

To secure your system I _strongly_ recommend to switch to using a Standard user account only.

Note: Jaguar does not lock secure preference panes when System Preferences quits, so always lock secure panes manually. If you fail to do that, the exploit will work until you log out.

Note: If you can't switch to a standard user account a simple AppleScript which locks secure preference panes as a Login Item could do the job.

Note: The normal version of RootPipe Tester will not run on Jaguar. Download the Legacy version of RootPipe Tester if you want to run on Jaguar.  
The Legacy version of RootPipe Tester is equivalent in functionality to the normal version, but is compiled using GCC 3.1 instead of GCC 4.0.

Test results:

#### nil authorization:  
Not vulnerable  
#### user authorization:  
- __Administrator account__: Vulnerable if secure preference panes have not been manually locked (by opening, if needed, and closing the lock in System Preferences) since the last login.  
- __Standard user account__: Vulnerable only if secure preference panes are unlocked.


### 4.7. Mac OS X 10.1 (Puma), Mac OS X 10.0 (Cheetah)
An exploit for Puma seems feasible, because it uses the same steps to authenticate System Preferences and most of the necessary components are there.
The only thing hindering an exploit is that Puma does not have `SecurityFoundation.framework` which is used on later versions to authorize.
Instead it uses a PrivateFramework called `NIInterface.framework` which needs to be reverse engineered first.

Good news anyway: Nobody is going to invest time into exploiting a probably next to nothing user base.  
To enhance security only using a Standard user account _and_ manually locking secure preference panes is still recommended.


## 5. About RootPipe
### 5.1. How does RootPipe work?
Note: Take this paragraph with a grain of salt. I tried my best to figure out what's really going on, but since it's all PrivateFrameworks, you can never 100% know what these methods are doing, especially not over so many versions of Mac OS X as I'm trying to cover.

The way the RootPipe exploit works is basically the same to what System Preferences does to write config files (thus the name `WriteConfig`) with the exception that users of this exploit must not be the System Preferences application.  
So far it's not that horrible, and actually the whole exploit is not so horrible either.  
But let's look at the code.

``` objc
	// Authorization
	SFAuthorization auth = [SFAuthorization authorization];
	id authenticator = [Authenticator sharedAuthenticator];
	[authenticator authenticateUsingAuthorizationSync:auth];
	// Profit?
	id sharedLiaison = [ToolLiaison sharedToolLiaison];
	id tool = [sharedLiaison tool];
```

As you can see, this is "old style" code, but the principle for the new style is more or less the same.  
The first three lines in this snippet are authorization and the last two are the real fun.

If a preference pane in System Preferences needs to do operations that have to be run privileged, it will place an `SFAuthorizationView` (the lock symbol) into the lower left corner. This `SFAuthorizationView` will then handle the acquisition and destroying of the `system.preferences` right.

So far so good, but what is this `system.preferences`?
The rights Apple uses and how they are configured changed over time, but the principle stayed the same. Below you see an excerpt of the Authorization Services Policy Database.

system.preferences on 10.5.8
``` 
{
    "allow-root" = 1;
    class = user;
    comment = "Checked by the Admin framework when making changes to certain System Preferences.";
    group = admin;
    shared = 1;
}
```

As you can see, it is a shared right. This means that once this right has been acquired by any process every other process can use it for as long as the session doesn't get destroyed (when you log out).  
This by itself is not so bad, because you have to authorize the first time an application wants to use `system.preferences`, unfortunately the system automatically authorizes it automatically at login (for Administrator users).
This means that our RootPipe Tester will not have to get authorized and can instead use the authorization of the system.

Standard users are safe, because the system doesn't authorize the `system.preferences` right at login.

With the proper authorization acquired it's a pretty easy game to write config files (or any other file for that matter) with arbitrary rights.  
`ToolLiaison` is happily going to set up an `NSDistantObject` to `writeconfig` for you and `writeconfig` will happily write the file for you, because in their mind, you have authorized yourself just fine.


Checking the "Require password to unlock each System Preferences pane" checkbox in System Preferences fixes RootPipe on all versions of Mac OS X from 10.4 - 10.8.  
Checking this checkbox will modify the `system.preferences` right and set `shared` to false.  
If a right is not shared, this means that every process has to get its own authorization. Because getting authorization requires the user to enter the password of an Administrator the attack can be noticed by the user.
Also, simply running `sudo` will have the same effect, which makes this attack useless.

### 5.2. Is it a backdoor?
Not really. At first glance it might look like one, because it's in a PrivateFramework running as root and not doing proper authentication.

But the real issue here is more one of bad design. Apple wanted to ensure that every Administrator user has the ability to use System Preferences to the full and in Unix  everything needs a config file and these need to be written (most of the time as root).

One might argue that this is a bad idea (I would agree) but I would not consider it a backdoor since the authentication is working properly and every Administrator has the ability to get root via `sudo` anyway.
The main problem here is that Apple weighed comfort over security, but this also is nothing very special for them to do.
