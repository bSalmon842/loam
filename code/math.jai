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

convert_angle :: (angle : Radians) -> Degrees #must {
    return cast(Degrees) (angle * (360.0 / TAU));
}

convert_angle :: (angle : Degrees) -> Radians #must {
    return cast(Radians) (angle * (TAU / 360.0));
}

log2 :: (x : float) -> float #must {
    return log(x) / log(2);
}
