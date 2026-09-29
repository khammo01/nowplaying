# Migrating the personal Mac mini without losing its version

Do not clone over, reset, or replace the Mac mini's existing `~/NowPlaying` directory. Its source may contain changes absent from the first repository commit.

1. Stop its polling loop in the terminal before the final switch. Keep the old directory as a complete, private backup; it contains credentials.
2. Run `git clone https://github.com/khammo01/nowplaying.git ~/NowPlaying-sync` to clone into a separate sibling directory.
3. In the clone, create a reconciliation branch (`git switch -c reconcile-mac-mini`). Decompile the mini's two active scripts into an **ignored** directory in the clone:

   ```sh
   mkdir -p local-import
   osadecompile ~/NowPlaying/safari_youtube_nowplaying.scpt > local-import/safari.applescript
   osadecompile ~/NowPlaying/VLC_nowplaying.scpt > local-import/vlc.applescript
   ```

4. Compare the old shell and decompiled AppleScripts with the repository sources. Port each wanted functional difference into the tracked files, preserving the news-video filter and local configuration handling. **Do not commit the imported files**: the older shell/VLC script may embed Home Assistant and OMDb credentials.
5. Create `config.local.sh` from the example using the mini's own settings, and set `SSH_KEY` to its existing private key path. Preserve its state and cache locally if desired. Do not blindly copy the other Mac's Home Assistant audio entity.
6. Run `./scripts/check.sh`, review the staged diff for credentials, commit the reconciliation, and push the branch. Merge it to `main` after review, then update both Macs.
7. With the old loop stopped, rename the old directory to a dated backup and move the reconciled clone to `~/NowPlaying`. Adjust `SSH_KEY` if it referred to a path moved during the switch. Start one copy of `./NowPlaying.sh` and check its Home Assistant output.

The initial repository snapshot came from the work Mac. The reconciliation keeps the Mac mini's behavior as the baseline and carries forward the work Mac's 10-second NYTimes/Washington Post video filter. Keep the old mini directory as the private backup until the reconciled checkout has run successfully with its local configuration.
