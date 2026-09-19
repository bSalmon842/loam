/*
Project: Loam
File: lighting.jai
Author: Brock Salmon
Created: 18SEP2026
*/

MAX_LIGHTS_IN_SCENE :: 8;

Light :: struct {
    position    : Vector3;
    padding     : s32;
    orientation : Quaternion;
    colour      : Vector3 = { 1, 1, 1 };
    intensity   : float;
} #no_padding



