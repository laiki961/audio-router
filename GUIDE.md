# Audio Router: Getting Started

Audio Router lets different apps play through different speakers at the same time.
For example, you can listen to Spotify in Brave on your Bluetooth soundbar while a course video
in Chrome plays on your MacBook's built-in speakers.

It works with **Safari, Google Chrome, Brave and the Spotify app**. Every other app keeps
using your Mac's normal sound output.

You don't need any technical knowledge to use it. This guide takes about 5 minutes.

---

## 1. Check your Mac

You need **macOS Sonoma 14.4 or later**.

To check: click the **Apple menu ()** in the top-left corner → **About This Mac**.
The version number is shown under the name. If it's lower than 14.4, update first in
**System Settings → General → Software Update**.

## 2. Download and install

1. Go to the **[Releases page](https://github.com/laiki961/audio-router/releases/latest)**.
2. Under **Assets**, click **AudioRouter.zip**. It downloads to your **Downloads** folder.
3. Open **Downloads** and double-click **AudioRouter.zip**. A file called **AudioRouter** appears.
4. Drag **AudioRouter** into your **Applications** folder.

## 3. Open it for the first time

Audio Router is a free personal project, so it isn't registered with Apple. macOS will
warn you the first time you open it. This is expected, and you only have to do it once.

1. Open **Applications** and double-click **AudioRouter**.
2. macOS says it *"cannot verify"* the app. Click **Done** (or **OK**). Don't click Move to Trash.
3. Open **System Settings → Privacy & Security** and scroll down to the **Security** section.
4. Next to *"AudioRouter was blocked…"*, click **Open Anyway**, then enter your Mac password.
5. Click **Open Anyway** once more in the window that pops up.

> **Where did it go?** Audio Router doesn't open a window or show an icon in the Dock.
> Look for a **speaker icon (🔊)** in the **menu bar** at the top-right of your screen, near the
> clock and Wi-Fi icons. Click it to open Audio Router.

## 4. Allow permissions

macOS asks for permission the first time Audio Router needs something. Click **Allow** for each:

| macOS asks about… | Why Audio Router needs it |
| --- | --- |
| **Bluetooth** | To list your Bluetooth speakers and headphones, and connect them. |
| **System Audio Recording** | To take an app's sound and send it to the speaker you picked. It doesn't record or save anything. |
| **Control "Brave Browser"** (or Safari, Chrome, Spotify) | To pause your music and videos when you quit Audio Router. |

If you clicked **Don't Allow** by mistake, turn it back on in **System Settings → Privacy & Security**:
- **Bluetooth** → switch on **AudioRouter**
- **Screen & System Audio Recording** → under **System Audio Recording Only**, switch on **AudioRouter**
- **Automation** → under **AudioRouter**, switch on each browser

Then quit Audio Router and open it again.

## 5. Choose a speaker for each app

1. Click the **🔊 speaker icon** in the menu bar.
2. You'll see Safari, Chrome, Brave and Spotify (only the ones installed on your Mac).
   A green **〰️** wave next to an app means it's playing sound right now.
3. Click the menu next to an app and pick where its sound should go:
   - **System default**: the app uses your Mac's normal sound output.
   - **MacBook Pro Speakers**, or any other speaker that's connected.
   - Under **Bluetooth – connects when picked**: your paired Bluetooth speakers and headphones.
     Picking one connects it automatically, so make sure it's switched on.

**Example: music on the soundbar, course on the laptop**

| App | Choose |
| --- | --- |
| Brave (Spotify) | **Soundbar** |
| Chrome (course videos) | **MacBook Pro Speakers** |

> **Tip:** pick a speaker for *both* apps rather than leaving one on "System default".
> When a Bluetooth speaker connects, macOS often makes it the default speaker, and any app on
> "System default" would move to it too.

Audio Router remembers your choices, even after you restart your Mac.

## 6. Change the volume

When an app is set to a specific speaker, a **volume slider** appears under it. Drag it to make
that speaker louder or quieter.

- The **volume keys on your keyboard** still control your Mac's normal (default) speaker.
- The slider controls the speaker you picked, just like its own volume buttons.

## 7. Quitting

Click the **🔊 speaker icon → Quit**. Audio Router first **pauses** your music and videos, so
they don't suddenly start playing from the wrong speaker.

For this to work in browsers, turn on one setting in each browser you use (once):

- **Brave or Chrome:** in the menu bar, click **View → Developer → Allow JavaScript from Apple Events**.
- **Safari:** click **Safari → Settings → Advanced** and tick **Show features for web developers**.
  Then, in the menu bar, click **Develop → Allow JavaScript from Apple Events**.

If something couldn't be paused, Audio Router tells you why and lets you **Quit Anyway** or **Cancel**.

## 8. Start Audio Router automatically (optional)

To have it running whenever you turn on your Mac:
**System Settings → General → Login Items & Extensions** → under **Open at Login**, click **+**
→ choose **AudioRouter** from Applications → **Open**.

---

## Troubleshooting

**I can't find the speaker icon in the menu bar.**
If your menu bar is full, the icon may be hidden behind the notch on newer MacBooks.
Quit a few other menu bar apps, or hold **⌘ Command** and drag menu bar icons to make room.

**An app isn't in the list.**
Only Safari, Chrome, Brave and the Spotify app are supported, and only if they're installed
in your Applications folder. Spotify in a web browser follows that browser's setting.

**I picked a speaker but the sound still comes from the old one.**
Check the **System Audio Recording** permission (step 4), then quit and reopen Audio Router.
If you see red text under the app in Audio Router, it describes what went wrong.

**My Bluetooth speaker won't connect.**
Make sure it's switched on, nearby, and not connected to another device such as your phone.
Then click **Connect** under the app in Audio Router. If it still fails, connect it once from
**System Settings → Bluetooth** first.

**The sound cuts out or jumps to another speaker.**
That happens when a speaker disconnects (turned off, out of range, battery empty).
The app goes back to "System default" until the speaker reconnects, then switches back on its own.

**A video inside a course page doesn't pause when I quit.**
Some course sites show videos from another website (such as Vimeo or YouTube) inside their page.
Browsers don't allow other apps to pause those, so pause them yourself before quitting.

**AirPlay speakers (HomePod, Apple TV) aren't listed.**
macOS doesn't let other apps send sound to AirPlay speakers, so these can't be used.

## Uninstall

Click the **🔊 speaker icon → Quit**, then drag **AudioRouter** from Applications to the Trash.
