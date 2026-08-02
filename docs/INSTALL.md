# Install Astra from GitHub

Astra supports Apple silicon and Intel Macs running macOS 15 or newer.

1. Download the latest `Astra-<version>.dmg` and checksum from GitHub Releases.
2. Put both files in the same folder and verify the checksum with
   `shasum -a 256 -c Astra-<version>.dmg.sha256`.
3. Open the disk image and drag Astra to Applications.
4. Try to open Astra once. Because releases are not notarized, macOS may block
   the first launch.
5. Open **System Settings → Privacy & Security**, choose **Open Anyway**, and
   confirm that you want to run Astra.
6. Follow Astra's setup to enable **App blocking**. If macOS says
   approval is required, allow Astra under **General → Login Items & Extensions**.
7. Click **Allow** for every installed supported browser. Astra quietly
   opens a closed browser, then macOS presents its Automation consent prompt.

Astra must remain in Applications for app blocking to register. It
will not label a timer as protected until the helper and relevant browser
access are ready. Because GitHub builds are ad-hoc signed rather than notarized,
macOS may ask for Automation consent again after an update, and Astra will ask
you to enable app blocking again for the new build.

No paid Apple developer account is required to build Astra locally. Xcode is
free, but its license must be accepted before using the toolchain.

## Recovery

If Astra cannot open its setup window, Protection can be disabled safely from
Terminal before relaunching the app:

```bash
/Applications/Astra.app/Contents/MacOS/Astra --disable-protection
```

This unregisters only Astra's user-level background item. It does not modify
other login items or macOS privacy settings. To enable the same item from
Terminal, use `--enable-protection` instead. Run `--protection-status` for a
read-only JSON health report from the live helper.
