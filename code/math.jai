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

determinant :: (a: Vector2, b: Vector2) -> float {
    return a.x*b.y - a.y*b.x;
}

triple_cross :: (a : Vector3, b : Vector3, c : Vector3) -> Vector3 {
    return cross(cross(a, b), c);
}

quaternion_to_euler :: (q : Quaternion) -> Vector3 {
    sinPitch := 2.0 * (q.w * q.x - q.y * q.z);
    if abs(sinPitch) >= 0.9999 {
	pitch := (PI * 0.5) * ifx sinPitch < 0 then -1.0 else 1.0;
	yaw := 2.0 * atan2(q.y, q.w);
	return .{ pitch, yaw, 0 };
    }
    
    pitch := asin(sinPitch);
    yaw   := atan2(2.0 * (q.x * q.z + q.w * q.y), 1.0 - 2.0 * (square(q.x) + square(q.y)));
    roll  := atan2(2.0 * (q.x * q.y + q.w * q.z), 1.0 - 2.0 * (square(q.x) + square(q.z)));
    return .{ pitch, yaw, roll };
}

euler_to_quaternion :: (v : Vector3) -> Quaternion {
    sy := sin(v.y * 0.5);
    sp := sin(v.x * 0.5);
    sr := sin(v.z * 0.5);

    cy := cos(v.y * 0.5);
    cp := cos(v.x * 0.5);
    cr := cos(v.z * 0.5);

    q : Quaternion;
    q.w = cy*cp*cr + sy*sp*sr;
    q.x = cy*sp*cr + sy*cp*sr;
    q.y = sy*cp*cr - cy*sp*sr;
    q.z = cy*cp*sr - sy*sp*cr;
    return q;
}

