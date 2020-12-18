import brian.ez3d;
import std.stdio;
import std.algorithm;
import std.math;

void main() {
	new GameWindow().run((GameWindow scene) {
		scene.camera = Matrix4(0, 4, 4).lookingAt(Vector3(0, 0, 0));

		Material mat = new Material;
		mat.specular = 0;
		mat.shininess = 16;

		scene.lockCursor;

		Vector3 cameraAt = Vector3(0, 4, 4);
		double rotX = 0;
		double rotY = 0;

		scene.onMouseMove = (prev, now) {
			Vector2 delta = now - prev;

			rotX += -delta.x / 250.0;
			rotY = min(max(rotY - delta.y / 250.0, -PI_2), PI_2);
		};

		scene.onScroll = (delta) {
			writeln("scroll ", delta);
		};

		scene.onKeyPress = (key, mods) {
			writeln("down ", key, " ", mods);
		};

		scene.onKeyRelease = (key, mods) {
			writeln("up ", key, " ", mods);
		};

		scene.onTick = {
			Vector3 delta;
			if (scene.isKeyDown(KeyCode.W))
				delta += Vector3(0, 0, -1);
			if (scene.isKeyDown(KeyCode.A))
				delta += Vector3(-1, 0, 0);
			if (scene.isKeyDown(KeyCode.S))
				delta += Vector3(0, 0, 1);
			if (scene.isKeyDown(KeyCode.D))
				delta += Vector3(1, 0, 0);
			if (scene.isKeyDown(KeyCode.Q))
				delta += Vector3(0, -1, 0);
			if (scene.isKeyDown(KeyCode.E))
				delta += Vector3(0, 1, 0);
			if (scene.isKeyDown(KeyCode.LeftShift))
				delta *= 0.25;
			cameraAt += (Matrix4.angles(0, rotX, 0) * Matrix4.angles(rotY, 0, 0) * Matrix4(delta * scene.timeStep * 16)).translation;
		};

		scene.onRender = {
			scene.camera = Matrix4(cameraAt) * Matrix4.angles(0, rotX, 0) * Matrix4.angles(rotY, 0, 0);
			scene.clear(Vector4.fromHex("#007fff"));
			foreach (i; -10 .. 11) {
				foreach (j; -10 .. 11) {
					scene.render(Mesh.cube, Matrix4(i, 0, j) * Matrix4.scale(Vector3(1, 1, 1) * abs(sin(timestamp))), mat, Vector4.fromHex("#f70"));
				}
			}
		};
	});
}
