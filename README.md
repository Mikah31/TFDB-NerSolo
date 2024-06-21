# TFDB-NerSolo
This is a plugin that adds NER (never ending rounds) and solo into TF2 Dodgeball

# Installation
Add the extra translations into the already existing `tfdb.phrases.txt` file

# Commands
- **sm_ner** : Toggles never ending rounds mode.
- **sm_votener** : Starts a vote for toggling NER.
- **sm_solo** : Adds yourself to the solo queue to be respawned later.

# Convars
```ini
tfdb_NERrandomize "1" - Randomizes teams when NER respawns everyone
tfdb_NERvotingTimeout "120" - Voting timeout for NER
tfdb_ForceNER "0" - Forces NER mode (when possible), can't be disabled anymore
tfdb_ForceNERstartMap "0" - Enables NER mode at the start of the map
tfdb_NERenabled "1" - Enables/disables NER
tfdb_SoloEnabled "1" - Enables/disables Solo
tfdb_HornSoundLevel "0.5" - Volume level of the horn played when respawning players
```
