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
tfdb_NERvotingTimeout "120" - Voting timeout for NER
tfdb_ForceNER "0" - Forces NER mode (when possible), can not be disabled anymore
tfdb_ForceNERstartMap "0" - Enables NER mode at the start of the map
tfdb_NERenabled "1" - Enables/disables NER
tfdb_SoloEnabled "1" - Enables/disables Solo
tfdb_SoloPriority "1" - Enables/disables priority for soloers being respawned before NER players are switched
tfdb_HornSoundLevel "0.5" - Volume level of the horn played when respawning players
tfdb_RespawnProtection "2.0" - Time after being respawned (by NER or solo) before damage can be taken
```
