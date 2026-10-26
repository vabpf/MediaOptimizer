MEDIA OPTIMIZER - scripted release
===================================

Double-click:  MediaOptimizer.cmd

You can also drag a folder or a single file onto MediaOptimizer.cmd.


WHAT IT DOES
------------
Shrinks the videos and photos in a folder, or a single file.
Results are written to an "optimized" subfolder next to your selection.
Your originals are never changed or deleted.

Supported: MP4, MOV, JPG, JPEG. Folders are scanned recursively.


BEFORE THE FIRST RUN
--------------------
This app uses three free helper tools. It checks for them and tells you
what is missing, but here is the list:

  ffmpeg       for videos
               winget install Gyan.FFmpeg

  cjpegli      for photos (not available on winget)
               https://github.com/libjxl/libjxl/releases

  exiftool     optional; keeps original timestamps and photo metadata
               winget install PhilHarvey.ExifTool

You only need the ones for the media you are processing. A folder of
photos does not need ffmpeg, and a folder of videos does not need
cjpegli.


IF WINDOWS BLOCKS THE FILE
--------------------------
Files that came from the internet are marked as untrusted. If Windows
shows "Windows protected your PC":

   1. Right-click the downloaded .zip BEFORE extracting it
   2. Properties
   3. Tick "Unblock"
   4. OK

Then extract and run. If you already extracted, unblock
MediaOptimizer.cmd the same way (right-click, Properties, Unblock).


START MENU SHORTCUT (optional)
------------------------------
Double-click Create-Shortcut.cmd once. It copies Media Optimizer to

    C:\Users\<you>\AppData\Local\Programs\MediaOptimizer

and adds it to the Start menu, so it appears in Start search and under
All apps. After that you can delete the folder you downloaded.

To put it on the Start screen as a tile, press the Windows key, type
"media optimizer", right-click the result, and choose Pin to Start.
Windows does not allow an app to pin itself, so that last click is
yours to make.

No admin rights, no registry keys, no services. To undo it:

    Create-Shortcut.cmd -Remove

To keep the files where they are and only create the shortcut:

    Create-Shortcut.cmd -NoInstall

(The shortcut then points at this folder, so do not move or rename it.)


FILES
-----
  MediaOptimizer.cmd   Double-click this. Asks for a folder or a file.
  Create-Shortcut.cmd  Optional. Installs it and adds a Start entry.
  launcher.ps1         Prompt and checks. Used by MediaOptimizer.cmd.
  optimize.ps1         The engine that does the work.
  optimize.cmd         Non-interactive, for scheduled tasks:
                       optimize.cmd "D:\Folder"
  MediaOptimizer.ico   Icon for the Start menu shortcut.

Keep all the files in the same folder.


WHERE RESULTS GO
----------------
  D:\Photos\a.jpg            -> D:\Photos\optimized\a.jpg
  D:\Clips\day1\b.mp4        -> D:\Clips\optimized\day1\b.mp4

The folder structure is mirrored. Existing "optimized" folders are
skipped when scanning, so re-running does not process its own output.


NOTES
-----
Video encoding uses AMD AMF hardware acceleration. NVIDIA and Intel GPUs
are not supported in this release.

Subtitle and attachment tracks inside videos are not copied.
