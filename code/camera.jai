/*
Project: Loam
File: camera.jai
Author: Brock Salmon
Created: 12JUN2025
*/

Camera :: struct {
    verticalFOV : float;
    dimensions : Vector2;
    
    orientation : Quaternion;
    position : Vector3;

    isOrthographic : bool;
}

get_view_matrix :: (camera : *Camera) -> Matrix4 {
    rotationMatrix := rotation_matrix(Matrix4, camera.orientation);
    zAxis := normalize(multiply(rotationMatrix, .{ 0, 0, 1 }));
    xAxis := normalize(cross(.{ 0, 1, 0 }, zAxis));
    yAxis := normalize(cross(zAxis, xAxis));

    dx := -dot(xAxis, camera.position);
    dy := -dot(yAxis, camera.position);
    dz := -dot(zAxis, camera.position);
    return Matrix4.{
	xAxis.x, yAxis.x, zAxis.x, 0,
	xAxis.y, yAxis.y, zAxis.y, 0,
	xAxis.z, yAxis.z, zAxis.z, 0,
	dx,      dy,      dz,      1
    };
}

get_projection_matrix :: (camera : *Camera) -> Matrix4 {
    return ifx camera.isOrthographic then get_orthographic_matrix(camera) else get_perspective_matrix(camera);
}

get_perspective_matrix :: (camera : *Camera) -> Matrix4 {
    aspect := camera.dimensions.x / camera.dimensions.y;
    frustumTangent := tan(to_radians(camera.verticalFOV / 2.0));
    scaleY := 1.0 / frustumTangent;
    scaleX := scaleY / aspect;

    return Matrix4.{
	scaleX,  0,      0,     0,
	0,      -scaleY, 0,     0,
	0,       0,      0,     1,
	0,       0,      0.01,  0
    };
}

get_orthographic_matrix :: (camera : *Camera) -> Matrix4 {
    return Matrix4.{
	 2.0 / camera.dimensions.x,  0,                         0, 0,
	 0,                         -2.0 / camera.dimensions.y, 0, 0,
	 0,                          0,                         0, 0,
	-1,                          1,                         1, 1
    };
}
