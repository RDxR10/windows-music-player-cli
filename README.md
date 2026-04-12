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

## Appearance

### Windows 11

<img width="952" height="360" alt="play_WIN_11" src="https://github.com/user-attachments/assets/4732f511-84fa-4ebc-863f-33165646b305" />

### Windows 10

![play_WIN_10](https://github.com/user-attachments/assets/9384369b-d1be-4b80-9814-dc402afad2f7)

## Features

* Select track

![nav_WIN_10](https://github.com/user-attachments/assets/f003055f-ef6a-436e-bcda-52c571bf0a24)

* Pause 

![Paused](https://github.com/user-attachments/assets/0cf49608-d002-4208-acf8-e2ae733f7c8a)

* Shuffle Queue

![Shuffled_Queue](https://github.com/user-attachments/assets/b91f9fd7-6dc0-41b2-a10e-31ed0e278249)

* Search

![Search_Single_Song](https://github.com/user-attachments/assets/1ccead1b-6e07-45b9-bdeb-0b755e9766d1)

* Replay searched track

![Replay](https://github.com/user-attachments/assets/0d1cf92f-9368-4b9b-8b53-abcf38c87e99)

* Notification

![Notification](https://github.com/user-attachments/assets/eddde2da-948c-4b6a-9017-1dffc8aea127)

* Repeat Mode

![Repeat](https://github.com/user-attachments/assets/b16108ac-3d88-463b-abdd-3a0b839085e9)

* Loop Mode

![Loop_Mode](https://github.com/user-attachments/assets/24b21b03-34bd-4f49-9d7d-dc1bfc30dd29)

* Auto exit after the searched track ends

![Auto_Exit](https://github.com/user-attachments/assets/2c2f6e74-a27a-44b1-b833-50025e0e3904)

## New Features/Updates

* 05-04-2026 [FEAT]: Queue now opens in a separate view with arrow key navigation to select and play a song; current song continues playing during navigation and auto-advance to the next song is suspended until the queue is closed.

* 07-04-2026 [FEAT]: Search, pause and endless scrolling have been added to the navigator view. The last played song is now highlighted, and search mode combined with the navigator enables custom queue creation.
