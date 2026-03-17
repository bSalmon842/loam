/*
Project: Loam
File: camera.jai
Author: Brock Salmon
Created: 12JUN2025
*/

/* TODO: Multiple Cameras:
Currently while we support having multiple cameras, we don't support showing multiple at the same time (only UI camera and the active game camera)
To do this we would probably want pipelines (and game-defined pipelines by LOAM-21) to hold a camera that it renders with
*/

CameraMap :: Table(string, *Camera);

Camera :: struct {
    verticalFOV : float;
    dimensions : Vector2;
    
    orientation : Quaternion;
    position : Vector3;

    isOrthographic : bool;
    isWindowSize : bool;
}

make_camera :: (fov : float32, position : Vector3, isWindowSize := true, dimensions := Vector2.{}, ortho := true) -> *Camera {
    camera := New(Camera);
    camera.verticalFOV = fov;
    if dimensions.x > 0 && dimensions.y > 0 && !isWindowSize {
	camera.dimensions = dimensions;
    } else {
	camera.dimensions = .{ cast(float32) loam.windowWidth, cast(float32) loam.windowHeight };
    }
    camera.position = position;
    camera.isOrthographic = ortho;
    camera.isWindowSize = isWindowSize;
    return camera;
}

add_camera :: (name : string, fov : float32, position : Vector3, isWindowSize := true, dimensions := Vector2.{}, ortho := true) -> *Camera {
    camera := make_camera(fov, position, isWindowSize, dimensions, ortho);
    if table_contains(loam.cameras, name) {
	log(.WARN, tprint("Attempted to add camera with existing name \"%\"", name));
	return null;
    }

    table_add(loam.cameras, name, camera);
    return camera;
}

get_camera :: (name : string) -> *Camera {
    found, camera := table_find(loam.cameras, name);
    if !found {
	log(.ERROR, tprint("Failed to get camera \"%\"", name));
    }
    
    return camera;
}

relative_to_game_camera :: (point : Vector3) -> Vector3 {
    if !loam.activeGameCamera {
	log(.ERROR, "No active game camera found");
	return point;
    }
    return point - loam.activeGameCamera.position;
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
