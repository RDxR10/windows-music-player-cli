# Windows Music Player CLI

Most of us don’t like clicking buttons over and over again, especially on Windows when listening to music; sometimes we just want that Linux-like experience. This CLI music player serves that purpose.

Get your playlist shuffled and switch tracks with ease... enjoy your favorite music - uninterrupted and ad-free.

Best suited for those who have a regular music playlist/library and prefer the flexibility to change songs on the fly.

> [!WARNING]
> This repository does not encourage playing songs in corporate environments. Use at your own risk.

## Setup

Add your music directory in the first line of the script:

```powershell

$MusicDir = "G:\music"
```

## Usage

```powershell

.\play.ps1
```

![Sequence](https://github.com/user-attachments/assets/361cea7a-fc40-4abc-8839-30713d60a043)

![Paused](https://github.com/user-attachments/assets/0cf49608-d002-4208-acf8-e2ae733f7c8a)

![Shuffled_Queue](https://github.com/user-attachments/assets/6cd71e6d-1949-48c6-8a7e-8c7b98cc9e0a)

![Search](https://github.com/user-attachments/assets/e745a651-8cf3-4ba9-a263-dd32182a2edd)

![Replay](https://github.com/user-attachments/assets/7aa6ed28-3e33-4389-8e0e-9ffe7dff8f4f)

![Notification](https://github.com/user-attachments/assets/eddde2da-948c-4b6a-9017-1dffc8aea127)

![Repeat](https://github.com/user-attachments/assets/b2a3d317-c1bb-4080-b471-3a756d59fc7f)

![Auto_Exit](https://github.com/user-attachments/assets/2c2f6e74-a27a-44b1-b833-50025e0e3904)

## New Features/Updates

* 05-04-2026 [FEAT]: Queue now opens in a separate view with arrow key navigation to select and play a song; current song continues playing during navigation and auto-advance to the next song is suspended until the queue is closed.

* 07-04-2026 [FEAT]: Search, pause and endless scrolling have been added to the navigator view. The last played song is now highlighted, and search mode combined with the navigator enables custom queue creation.
