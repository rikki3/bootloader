#include <string.h>
#include "d_iwad.h"

static char doom2_name[] = "doom2.wad";

static const iwad_t supported_iwads[] = {
    { "doom2.wad", doom2, commercial, "Doom II" },
};

char* D_FindWADByName(char* filename) {
    if (filename != 0 && !strcasecmp(filename, doom2_name)) {
        return doom2_name;
    }
    return 0;
}

char* D_TryFindWADByName(char* filename) {
    char* result = D_FindWADByName(filename);
    return result != 0 ? result : filename;
}

char* D_FindIWAD(int mask, GameMission_t* mission) {
    if ((mask & (1 << doom2)) == 0) {
        return 0;
    }
    if (mission != 0) {
        *mission = doom2;
    }
    return doom2_name;
}

const iwad_t** D_FindAllIWADs(int mask) {
    static const iwad_t* result[2];
    if ((mask & (1 << doom2)) == 0) {
        result[0] = 0;
        return result;
    }
    result[0] = &supported_iwads[0];
    result[1] = 0;
    return result;
}

char* D_SaveGameIWADName(GameMission_t gamemission) {
    (void) gamemission;
    return doom2_name;
}

char* D_SuggestIWADName(GameMission_t mission, GameMode_t mode) {
    (void) mission;
    (void) mode;
    return doom2_name;
}

char* D_SuggestGameName(GameMission_t mission, GameMode_t mode) {
    (void) mission;
    (void) mode;
    return supported_iwads[0].description;
}

void D_CheckCorrectIWAD(GameMission_t mission) {
    (void) mission;
}
