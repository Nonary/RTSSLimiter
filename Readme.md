# RTSS Frame Limit Script for Streaming

This simple script applies an RTSS frame limit to your stream. It is recommended to disable VSYNC while streaming to improve fluidity and response times. A common caveat is that the stream will microstutter unless you set the streaming FPS as a limit on the host. This script automates applying a global frame limit when streaming that matches the streaming rate, and then reverts back once streaming is finished.

## Installation Instructions

1. **Update Path (if necessary)**:
    - If you have installed RTSS in a different location other than the default, you will need to update the path installation directory located in `settings.json`.
    - If RTSS is installed in the default location, you can leave the path unchanged.

2. **Run the Installer**:
    - Double-click `install.bat`.
    - That's it! You're all set.