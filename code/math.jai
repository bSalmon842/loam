/*
Project: Loam
File: math.jai
Author: Brock Salmon
Created: 17MAY2025
*/

Radians :: #type,isa float;
MIN_RADIANS : Radians : 0.0;
MAX_RADIANS : Radians : TAU;

Degrees :: #type,isa float;
MIN_DEGREES : Degrees : 0.0;
MAX_DEGREES : Degrees : 360.0;

Angle :: struct {
    rad : Radians;
    deg : Degrees;
}

set_angle :: (using angle : *Angle, degrees : Degrees) {
    deg = degrees;
    rad = convert_angle(deg);
}

set_angle :: (using angle : *Angle, radians : Radians) {
    rad = radians;
    deg = convert_angle(rad);
}

convert_angle :: (angle : Radians) -> Degrees {
    return cast(Degrees) (angle * (360.0 / TAU));
}

convert_angle :: (angle : Degrees) -> Radians {
    return cast(Radians) (angle * (TAU / 360.0));
}

log2 :: (x : float) -> float {
    return log(x) / log(2);
}

normalise_0_to_1 :: (x : float32, min : float32, max : float32) -> float32 {
    return (x - min) / (max - min);
}

normalise_neg_1_to_1 :: (x : float32, min : float32, max : float32) -> float32 {
    return 2.0 * normalise_0_to_1(x, min, max) - 1.0;
}

triple_cross :: (a : Vector3, b : Vector3, c : Vector3) -> Vector3 {
    return cross(cross(a, b), c);
}

