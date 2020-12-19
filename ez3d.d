/**

A simple and quick 3D rendering library

Depends on `brian.gl`

The $(REF GameWindow) class will be available if the optional dependency `arsd.simpledisplay` is available.

*/
module brian.ez3d;
static assert(__traits(compiles, () {
	import brian.gl;
}), "brian.ez3d depends on: brian.gl");
import brian.gl : gl;
import brian.gl;
import std.typecons;
import std.math;
import std.conv;

/** A 2-dimensional (XY) vector */
struct Vector2 {

	/** The X component of the vector */
	double x = 0.0;

	/** The Y component of the vector */
	double y = 0.0;

	/** Computes the magnitude of this vector */
	double magnitude() const {
		return sqrt(x * x + y * y);
	}

	/** Computes the unit vector of this vector */
	Vector2 unit() const {
		const mag = magnitude;
		return mag == 0 ? this : this / mag;
	}

	/** Creates a new vector with the given components */
	this(double x, double y) {
		this.x = x;
		this.y = y;
	}

	/** Applies the given operator onto each component in the two vectors */
	Vector2 opBinary(string op)(Vector2 other) const {
		return mixin("Vector2(x" ~ op ~ "other.x, y" ~ op ~ "other.y)");
	}

	/** Applies the given operator onto each component in the vector and the given value */
	Vector2 opBinary(string op)(double other) const {
		return mixin("Vector2(x" ~ op ~ "other, y" ~ op ~ "other)");
	}

	/** Applies the given operator onto each component in the vector */
	Vector2 opUnary(string op)() const {
		return mixin("Vector2(" ~ op ~ "x, " ~ op ~ "y)");
	}

	void opOpAssign(string op)(Vector2 other) {
		mixin("x" ~ op ~ "=other.x;");
		mixin("y" ~ op ~ "=other.y;");
	}

	void opOpAssign(string op)(double other) {
		mixin("x" ~ op ~ "=other;");
		mixin("y" ~ op ~ "=other;");
	}

	/** Computes the dot product of this and the given vector */
	double dot(Vector2 other) const {
		return x * other.x + y * other.y;
	}

	string toString() const {
		return "(" ~ x.to!string ~ ", " ~ y.to!string ~ ")";
	}

}

/** A 3-dimensional (XYZ) vector */
struct Vector3 {

	/** The X component of the vector */
	double x = 0.0;

	/** The Y component of the vector */
	double y = 0.0;

	/** The Z component of the vector */
	double z = 0.0;

	/** Computes the magnitude of this vector */
	double magnitude() const {
		return sqrt(x * x + y * y + z * z);
	}

	/** Computes the unit vector of this vector */
	Vector3 unit() const {
		const mag = magnitude;
		return mag == 0 ? this : this / mag;
	}

	/** Creates a new vector with the given components */
	this(double x, double y, double z) {
		this.x = x;
		this.y = y;
		this.z = z;
	}

	/** Applies the given operator onto each component in the two vectors */
	Vector3 opBinary(string op)(Vector3 other) const {
		return mixin("Vector3(x" ~ op ~ "other.x, y" ~ op ~ "other.y, z" ~ op ~ " other.z)");
	}

	/** Applies the given operator onto each component in the vector and the given value */
	Vector3 opBinary(string op)(double other) const {
		return mixin("Vector3(x" ~ op ~ "other, y" ~ op ~ "other, z" ~ op ~ " other)");
	}

	/** Applies the given operator onto each component in the vector */
	Vector3 opUnary(string op)() const {
		return mixin("Vector3(" ~ op ~ "x, " ~ op ~ "y, " ~ op ~ "z)");
	}

	void opOpAssign(string op)(Vector3 other) {
		mixin("x" ~ op ~ "=other.x;");
		mixin("y" ~ op ~ "=other.y;");
		mixin("z" ~ op ~ "=other.z;");
	}

	void opOpAssign(string op)(double other) {
		mixin("x" ~ op ~ "=other;");
		mixin("y" ~ op ~ "=other;");
		mixin("z" ~ op ~ "=other;");
	}

	/** Computes the dot product of this and the given vector */
	double dot(Vector3 other) const {
		return x * other.x + y * other.y + z * other.z;
	}

	/** Computes the cross product of this and the given vector */
	Vector3 cross(Vector3 other) const {
		return Vector3(
			y * other.z - z * other.y,
			z * other.x - x * other.z,
			x * other.y - y * other.x,
		);
	}

	string toString() const {
		return "(" ~ x.to!string ~ ", " ~ y.to!string ~ ", " ~ z.to!string ~ ")";
	}

}

/** An exception thrown when invalid hex is passed into $(D Vector4.fromHex) */
class HexFormatException : Exception {

	/** The hex string that was passed in and invalid */
	string culprit;

	/** Creates a new $(REF HexFormatException) */
	this(string msg, string culprit, string file = __FILE__, size_t line = __LINE__, Throwable nextInChain = null) @nogc @safe pure nothrow {
		super(msg, file, line, nextInChain);
		this.culprit = culprit;
	}
}

/** A 4-dimensional (XYZW) vector */
struct Vector4 {

	/** The X component of the vector */
	double x = 0.0;

	/** The Y component of the vector */
	double y = 0.0;

	/** The Z component of the vector */
	double z = 0.0;

	/** The W component of the vector */
	double w = 0.0;

	/** The R channel (X component) of the color */
	ref r() inout @property { return x; }

	/** The G channel (Y component) of the color */
	ref g() inout @property { return y; }

	/** The B channel (Z component) of the color */
	ref b() inout @property { return z; }

	/** The A channel (W component) of the color */
	ref a() inout @property { return w; }

	/** Computes the magnitude of this vector */
	double magnitude() const {
		return sqrt(x * x + y * y + z * z + w * w);
	}

	/** Computes the unit vector of this vector */
	Vector4 unit() const {
		const mag = magnitude;
		return mag == 0 ? this : this / mag;
	}

	/** Creates a new vector with the given components */
	this(double x, double y, double z, double w) {
		this.x = x;
		this.y = y;
		this.z = z;
		this.w = w;
	}

	/**

	Creates a Vector4 from the given hex color. All components will be normalized into the range [0, 1].

	Params:
	hex = A hex color.

	- May optionally contain a leading `#`.

	- May contain 3 or 6 characters for a 3-component color, with an implied 1.0 as alpha.

	- May contain 4 or 8 characters for a 4-component color.

	Throws: $(REF HexFormatException) on invalid color format.

	*/
	static Vector4 fromHex(string hex) {
		if (hex.length > 0 && hex[0] == '#') {
			hex = hex[1 .. $];
		}

		try {
			if (hex.length == 3) {
				int a = hex[0 .. 1].to!int(16);
				int b = hex[1 .. 2].to!int(16);
				int c = hex[2 .. 3].to!int(16);
				return Vector4(a * 17 / 255.0, b * 17 / 255.0, c * 17 / 255.0, 1);
			}
			else if (hex.length == 6) {
				int a = hex[0 .. 2].to!int(16);
				int b = hex[2 .. 4].to!int(16);
				int c = hex[4 .. 6].to!int(16);
				return Vector4(a / 255.0, b / 255.0, c / 255.0, 1);
			}
			else if (hex.length == 4) {
				int a = hex[0 .. 1].to!int(16);
				int b = hex[1 .. 2].to!int(16);
				int c = hex[2 .. 3].to!int(16);
				int d = hex[3 .. 4].to!int(16);
				return Vector4(a * 17 / 255.0, b * 17 / 255.0, c * 17 / 255.0, d * 17 / 255.0);
			}
			else if (hex.length == 8) {
				int a = hex[0 .. 2].to!int(16);
				int b = hex[2 .. 4].to!int(16);
				int c = hex[4 .. 6].to!int(16);
				int d = hex[6 .. 8].to!int(16);
				return Vector4(a / 255.0, b / 255.0, c / 255.0, d / 255.0);
			}
			else {
				throw new HexFormatException("invalid hex color", hex);
			}
		}
		catch (ConvException) {
			throw new HexFormatException("invalid hex color", hex);
		}
	}

	/** Applies the given operator onto each component in the two vectors */
	Vector4 opBinary(string op)(Vector4 other) const {
		return mixin(
				"Vector4(x" ~ op ~ "other.x, y" ~ op ~ "other.y, z" ~ op
				~ " other.z, w" ~ op ~ " other.w)");
	}

	/** Applies the given operator onto each component in the vector and the given value */
	Vector4 opBinary(string op)(double other) const {
		return mixin("Vector4(x" ~ op ~ "other, y" ~ op ~ "other, z" ~ op
				~ " other, w" ~ op ~ " other)");
	}

	/** Applies the given operator onto each component in the vector */
	Vector4 opUnary(string op)() const {
		return mixin("Vector4(" ~ op ~ "x, " ~ op ~ "y, " ~ op ~ "z, " ~ op ~ "w)");
	}

	void opOpAssign(string op)(Vector4 other) {
		mixin("x" ~ op ~ "=other.x;");
		mixin("y" ~ op ~ "=other.y;");
		mixin("z" ~ op ~ "=other.z;");
		mixin("w" ~ op ~ "=other.w;");
	}

	void opOpAssign(string op)(double other) {
		mixin("x" ~ op ~ "=other;");
		mixin("y" ~ op ~ "=other;");
		mixin("z" ~ op ~ "=other;");
		mixin("w" ~ op ~ "=other;");
	}

	/** Computes the dot product of this and the given vector */
	double dot(Vector4 other) const {
		return x * other.x + y * other.y + z * other.z + w * other.w;
	}

	string toString() const {
		return "(" ~ x.to!string ~ ", " ~ y.to!string ~ ", " ~ z.to!string ~ ", " ~ w.to!string ~ ")";
	}

}

/** A 4x4 matrix that may be used to represent translations, rotations, or other transformations. */
struct Matrix4 {

	private double[4][4] m = [
		[1, 0, 0, 0], [0, 1, 0, 0], [0, 0, 1, 0], [0, 0, 0, 1],
	];

	/** Creates a translation matrix using the given vector as its translation component */
	this(double x, double y, double z) {
		m[0][0] = 1;
		m[0][1] = 0;
		m[0][2] = 0;
		m[0][3] = x;
		m[1][0] = 0;
		m[1][1] = 1;
		m[1][2] = 0;
		m[1][3] = y;
		m[2][0] = 0;
		m[2][1] = 0;
		m[2][2] = 1;
		m[2][3] = z;
		m[3][0] = 0;
		m[3][1] = 0;
		m[3][2] = 0;
		m[3][3] = 1;
	}

	/** Creates a translation matrix using the given vector as its translation component */
	this(Vector3 vec) {
		this(vec.x, vec.y, vec.z);
	}

	/** Creates a matrix from the given components, given in row-major order */
	this(double[4][4] m) {
		this.m = m;
	}

	/** The component at the given row, column of this matrix */
	double opIndex(size_t r, size_t c) const { return m[r][c]; }

	/** The X component of the translation vector of this matrix */
	double x() const @property { return m[0][3]; }

	/** The Y component of the translation vector of this matrix */
	double y() const @property { return m[1][3]; }

	/** The Z component of the translation vector of this matrix */
	double z() const @property { return m[2][3]; }

	/** The translation component of this matrix */
	Vector3 translation() const {
		return Vector3(m[0][3], m[1][3], m[2][3]);
	}

	/** Creates a copy of the matrix and modifies the translation component */
	Matrix4 withTranslation(Vector3 value) const {
		Matrix4 res = this;
		res.m[0][3] = value.x;
		res.m[1][3] = value.y;
		res.m[2][3] = value.z;
		return res;
	}

	/** Creates a copy of the matrix with the translation component removed */
	Matrix4 withoutTranslation() const {
		return withTranslation(Vector3.init);
	}

	/** The scale component of this matrix */
	Vector3 scale() const {
		return Vector3(m[0][0], m[1][1], m[2][2]);
	}

	/** Creates a copy of the matrix and modifies the scale component */
	Matrix4 withScale(Vector3 value) const {
		Matrix4 res = this;
		res.m[0][0] = value.x;
		res.m[1][1] = value.y;
		res.m[2][2] = value.z;
		return res;
	}

	/** Creates a copy of the matrix with the scale component removed */
	Matrix4 withoutScale() const {
		return withScale(Vector3.init);
	}

	/** The forward vector of the matrix */
	Vector3 forward() const {
		return (withoutTranslation * Matrix4(0, 0, 1)).translation;
	}

	/**

	Creates a new matrix with the same translation component, which has the given forward vector.

	Params:
	value = The new forward vector. This value's magnitude will be normalized to 1 before the operation.
	up = The up vector to use in this operation.

	*/
	Matrix4 withForward(Vector3 value, Vector3 up = Vector3(0, 1, 0)) const {
		if (value.magnitude == 0)
			return Matrix4(translation);
		if (value.unit == up.unit)
			return Matrix4(translation) * Matrix4.angles(PI_2, 0, 0);
		if (value.unit == -up.unit)
			return Matrix4(translation) * Matrix4.angles(-PI_2, 0, 0);
		Vector3 forward = value.unit;
		Vector3 right = forward.cross(up.unit);
		Vector3 up2 = right.cross(forward);
		Vector3 forward2 = right.cross(up2);
		return Matrix4(translation) * Matrix4([
			[right.x, up2.x, forward2.x, 0],
			[right.y, up2.y, forward2.y, 0],
			[right.z, up2.z, forward2.z, 0],
			[0, 0, 0, 1.0],
		]);
	}

	/**

	Creates a new matrix with the same translation component, which looks at the given position.

	Params:
	value = The position to look at.
	up = The up vector to use in this operation.

	*/
	Matrix4 lookingAt(Vector3 value, Vector3 up = Vector3(0, 1, 0)) const {
		return withForward(value - translation, up);
	}

	/**
	
	Creates a new perspective projection matrix made with the given parameters.

	Params:
	fov = Field of view, in radians
	aspect = Aspect ratio of the viewport (width / height)
	near = The minimum distance for an object to be visible
	far = The maximum distance for an object to be visible

	*/
	static Matrix4 perspective(double fov, double aspect, double near, double far) {
		if (fov <= 0 || fov > PI)
			return Matrix4();
		if (aspect <= 0)
			return Matrix4();
		if (near <= 0)
			return Matrix4();
		if (far <= 0)
			return Matrix4();
		if (near >= far)
			return Matrix4();

		const double y = 1 / tan(fov / 2);
		const double x = y / aspect;

		return Matrix4([[x, 0.0, 0.0, 0.0], [0.0, y, 0.0, 0.0], [0.0, 0.0,
				-far / (far - near), -2 * near * far / (far - near)], [0.0, 0.0, -1.0, 0.0]]);
	}

	/**

	Creates a new orthographic projection matrix with the given parameters.

	Params:
	width = The width of the projection volume
	height = The height of the projection volume
	near = The minimum distance for an object to be visible
	far = The maximum distance for an object to be visible

	*/
	static Matrix4 orthographic(double width, double height, double near, double far) {
		if (far <= 0)
			return Matrix4();
		if (near >= far)
			return Matrix4();

		return Matrix4([
			[2.0 / width, 0.0, 0.0, 0.0],
			[0.0, 2.0 / height, 0.0, 0.0],
			[0.0, 0.0, -2.0 / (far - near), -(far + near) / (far - near)],
			[0.0, 0.0, 0.0, 1.0],
		]);
	}

	/**

	Creates a new orthographic projection matrix with the given parameters.

	Params:
	size = The width and height of the projection volume
	near = The minimum distance for an object to be visible
	far = The maximum distance for an object to be visible

	*/
	static Matrix4 orthographic(Vector2 size, double near, double far) {
		return orthographic(size.x, size.y, near, far);
	}

	/**

	Creates a new rotation matrix created from the given Euler angles. The angles are applied in X, Y, Z order.

	Params:
	x = The X angle to use in creating the matrix
	y = The Y angle to use in creating the matrix
	z = The Z angle to use in creating the matrix

	*/
	static Matrix4 angles(double x, double y, double z) {
		if (y == 0.0 && z == 0.0) { // rotate X
			return Matrix4([[1.0, 0.0, 0.0, 0.0], [0.0, cos(-x), sin(-x), 0.0], [0.0, -sin(-x), cos(-x), 0.0], [0.0, 0.0, 0.0, 1.0]]);
		}
		else if (x == 0.0 && z == 0.0) { // rotate Y
			return Matrix4([[cos(-y), 0.0, -sin(-y), 0.0], [0.0, 1.0, 0.0, 0.0], [sin(-y), 0.0, cos(-y), 0.0], [0.0, 0.0, 0.0, 1.0]]);
		}
		else if (x == 0.0 && y == 0.0) { // rotate Z
			return Matrix4([[cos(-z), sin(-z), 0.0, 0.0], [-sin(-z), cos(-z), 0.0, 0.0], [0.0, 0.0, 1.0, 0.0], [0.0, 0.0, 0.0, 1.0]]);
		}
		else { // rotate combination
			return Matrix4.angles(x, 0.0, 0.0) * Matrix4.angles(0.0, y, 0.0) * Matrix4.angles(0.0, 0.0, z);
		}
	}

	/**

	Creates a new scale matrix with the given components.

	Params:
	x = The X-component scale to use in creating the matrix
	y = The Y-component scale to use in creating the matrix
	z = The Z-component scale to use in creating the matrix

	*/
	static Matrix4 scale(double x, double y, double z) {
		return Matrix4([
			[x, 0, 0, 0],
			[0, y, 0, 0],
			[0, 0, z, 0],
			[0, 0, 0, 1.0],
		]);
	}

	/**

	Creates a new scale matrix.

	Params:
	value = The amount to scale by

	*/
	static Matrix4 scale(Vector3 value) {
		return scale(value.x, value.y, value.z);
	}

	/** Computes the inverse of the matrix */
	Matrix4 inverse() const {
		double[4][4] M;

		M[0][0] = m[1][1] * m[2][2] * m[3][3] - m[1][1] * m[3][2] * m[2][3]
			- m[1][2] * m[2][1] * m[3][3] + m[1][2] * m[3][1] * m[2][3]
			+ m[1][3] * m[2][1] * m[3][2] - m[1][3] * m[3][1] * m[2][2];

		M[0][1] = -m[0][1] * m[2][2] * m[3][3] + m[0][1] * m[3][2] * m[2][3]
			+ m[0][2] * m[2][1] * m[3][3] - m[0][2] * m[3][1] * m[2][3]
			- m[0][3] * m[2][1] * m[3][2] + m[0][3] * m[3][1] * m[2][2];

		M[0][2] = m[0][1] * m[1][2] * m[3][3] - m[0][1] * m[3][2] * m[1][3]
			- m[0][2] * m[1][1] * m[3][3] + m[0][2] * m[3][1] * m[1][3]
			+ m[0][3] * m[1][1] * m[3][2] - m[0][3] * m[3][1] * m[1][2];

		M[0][3] = -m[0][1] * m[1][2] * m[2][3] + m[0][1] * m[2][2] * m[1][3]
			+ m[0][2] * m[1][1] * m[2][3] - m[0][2] * m[2][1] * m[1][3]
			- m[0][3] * m[1][1] * m[2][2] + m[0][3] * m[2][1] * m[1][2];

		M[1][0] = -m[1][0] * m[2][2] * m[3][3] + m[1][0] * m[3][2] * m[2][3]
			+ m[1][2] * m[2][0] * m[3][3] - m[1][2] * m[3][0] * m[2][3]
			- m[1][3] * m[2][0] * m[3][2] + m[1][3] * m[3][0] * m[2][2];

		M[1][1] = m[0][0] * m[2][2] * m[3][3] - m[0][0] * m[3][2] * m[2][3]
			- m[0][2] * m[2][0] * m[3][3] + m[0][2] * m[3][0] * m[2][3]
			+ m[0][3] * m[2][0] * m[3][2] - m[0][3] * m[3][0] * m[2][2];

		M[1][2] = -m[0][0] * m[1][2] * m[3][3] + m[0][0] * m[3][2] * m[1][3]
			+ m[0][2] * m[1][0] * m[3][3] - m[0][2] * m[3][0] * m[1][3]
			- m[0][3] * m[1][0] * m[3][2] + m[0][3] * m[3][0] * m[1][2];

		M[1][3] = m[0][0] * m[1][2] * m[2][3] - m[0][0] * m[2][2] * m[1][3]
			- m[0][2] * m[1][0] * m[2][3] + m[0][2] * m[2][0] * m[1][3]
			+ m[0][3] * m[1][0] * m[2][2] - m[0][3] * m[2][0] * m[1][2];

		M[2][0] = m[1][0] * m[2][1] * m[3][3] - m[1][0] * m[3][1] * m[2][3]
			- m[1][1] * m[2][0] * m[3][3] + m[1][1] * m[3][0] * m[2][3]
			+ m[1][3] * m[2][0] * m[3][1] - m[1][3] * m[3][0] * m[2][1];

		M[2][1] = -m[0][0] * m[2][1] * m[3][3] + m[0][0] * m[3][1] * m[2][3]
			+ m[0][1] * m[2][0] * m[3][3] - m[0][1] * m[3][0] * m[2][3]
			- m[0][3] * m[2][0] * m[3][1] + m[0][3] * m[3][0] * m[2][1];

		M[2][2] = m[0][0] * m[1][1] * m[3][3] - m[0][0] * m[3][1] * m[1][3]
			- m[0][1] * m[1][0] * m[3][3] + m[0][1] * m[3][0] * m[1][3]
			+ m[0][3] * m[1][0] * m[3][1] - m[0][3] * m[3][0] * m[1][1];

		M[2][3] = -m[0][0] * m[1][1] * m[2][3] + m[0][0] * m[2][1] * m[1][3]
			+ m[0][1] * m[1][0] * m[2][3] - m[0][1] * m[2][0] * m[1][3]
			- m[0][3] * m[1][0] * m[2][1] + m[0][3] * m[2][0] * m[1][1];

		M[3][0] = -m[1][0] * m[2][1] * m[3][2] + m[1][0] * m[3][1] * m[2][2]
			+ m[1][1] * m[2][0] * m[3][2] - m[1][1] * m[3][0] * m[2][2]
			- m[1][2] * m[2][0] * m[3][1] + m[1][2] * m[3][0] * m[2][1];

		M[3][1] = m[0][0] * m[2][1] * m[3][2] - m[0][0] * m[3][1] * m[2][2]
			- m[0][1] * m[2][0] * m[3][2] + m[0][1] * m[3][0] * m[2][2]
			+ m[0][2] * m[2][0] * m[3][1] - m[0][2] * m[3][0] * m[2][1];

		M[3][2] = -m[0][0] * m[1][1] * m[3][2] + m[0][0] * m[3][1] * m[1][2]
			+ m[0][1] * m[1][0] * m[3][2] - m[0][1] * m[3][0] * m[1][2]
			- m[0][2] * m[1][0] * m[3][1] + m[0][2] * m[3][0] * m[1][1];

		M[3][3] = m[0][0] * m[1][1] * m[2][2] - m[0][0] * m[2][1] * m[1][2]
			- m[0][1] * m[1][0] * m[2][2] + m[0][1] * m[2][0] * m[1][2]
			+ m[0][2] * m[1][0] * m[2][1] - m[0][2] * m[2][0] * m[1][1];

		double determinant = m[0][0] * M[0][0] + m[1][0] * M[0][1] + m[2][0]
			* M[0][2] + m[3][0] * M[0][3];
		if (determinant == 0)
			return Matrix4(0, 0, 0);
		determinant = 1.0 / determinant;

		M[0][0] = M[0][0] * determinant;
		M[0][1] = M[0][1] * determinant;
		M[0][2] = M[0][2] * determinant;
		M[0][3] = M[0][3] * determinant;
		M[1][0] = M[1][0] * determinant;
		M[1][1] = M[1][1] * determinant;
		M[1][2] = M[1][2] * determinant;
		M[1][3] = M[1][3] * determinant;
		M[2][0] = M[2][0] * determinant;
		M[2][1] = M[2][1] * determinant;
		M[2][2] = M[2][2] * determinant;
		M[2][3] = M[2][3] * determinant;
		M[3][0] = M[3][0] * determinant;
		M[3][1] = M[3][1] * determinant;
		M[3][2] = M[3][2] * determinant;
		M[3][3] = M[3][3] * determinant;

		return Matrix4(M);
	}

	void opOpAssign(string op)(const Matrix4 other) if (op == "*") {
		mixin("this = this ", op, " other;");
	}

	/** Computes the translation component of the product of the matrix and the translation matrix of the given vector */
	Vector3 opBinary(string op)(Vector3 other) const if (op == "*") {
		return (this * Matrix4(other)).translation;
	}

	/** Computes the product of this and the given matrix */
	Matrix4 opBinary(string op)(Matrix4 other) const if (op == "*") {
		double[4][4] M;

		M[0][0] = other.m[0][0] * m[0][0] + other.m[1][0] * m[0][1]
			+ other.m[2][0] * m[0][2] + other.m[3][0] * m[0][3];
		M[1][0] = other.m[0][0] * m[1][0] + other.m[1][0] * m[1][1]
			+ other.m[2][0] * m[1][2] + other.m[3][0] * m[1][3];
		M[2][0] = other.m[0][0] * m[2][0] + other.m[1][0] * m[2][1]
			+ other.m[2][0] * m[2][2] + other.m[3][0] * m[2][3];
		M[3][0] = other.m[0][0] * m[3][0] + other.m[1][0] * m[3][1]
			+ other.m[2][0] * m[3][2] + other.m[3][0] * m[3][3];
		M[0][1] = other.m[0][1] * m[0][0] + other.m[1][1] * m[0][1]
			+ other.m[2][1] * m[0][2] + other.m[3][1] * m[0][3];
		M[1][1] = other.m[0][1] * m[1][0] + other.m[1][1] * m[1][1]
			+ other.m[2][1] * m[1][2] + other.m[3][1] * m[1][3];
		M[2][1] = other.m[0][1] * m[2][0] + other.m[1][1] * m[2][1]
			+ other.m[2][1] * m[2][2] + other.m[3][1] * m[2][3];
		M[3][1] = other.m[0][1] * m[3][0] + other.m[1][1] * m[3][1]
			+ other.m[2][1] * m[3][2] + other.m[3][1] * m[3][3];
		M[0][2] = other.m[0][2] * m[0][0] + other.m[1][2] * m[0][1]
			+ other.m[2][2] * m[0][2] + other.m[3][2] * m[0][3];
		M[1][2] = other.m[0][2] * m[1][0] + other.m[1][2] * m[1][1]
			+ other.m[2][2] * m[1][2] + other.m[3][2] * m[1][3];
		M[2][2] = other.m[0][2] * m[2][0] + other.m[1][2] * m[2][1]
			+ other.m[2][2] * m[2][2] + other.m[3][2] * m[2][3];
		M[3][2] = other.m[0][2] * m[3][0] + other.m[1][2] * m[3][1]
			+ other.m[2][2] * m[3][2] + other.m[3][2] * m[3][3];
		M[0][3] = other.m[0][3] * m[0][0] + other.m[1][3] * m[0][1]
			+ other.m[2][3] * m[0][2] + other.m[3][3] * m[0][3];
		M[1][3] = other.m[0][3] * m[1][0] + other.m[1][3] * m[1][1]
			+ other.m[2][3] * m[1][2] + other.m[3][3] * m[1][3];
		M[2][3] = other.m[0][3] * m[2][0] + other.m[1][3] * m[2][1]
			+ other.m[2][3] * m[2][2] + other.m[3][3] * m[2][3];
		M[3][3] = other.m[0][3] * m[3][0] + other.m[1][3] * m[3][1]
			+ other.m[2][3] * m[3][2] + other.m[3][3] * m[3][3];

		return Matrix4(M);
	}

	string toString() const {
		return "(" ~ m[0].to!string ~ "\n" ~ m[1].to!string ~ "\n" ~ m[2].to!string ~ "\n" ~ m[3].to!string ~ ")";
	}

}

/** An exception thrown when an invalid mesh file is loaded */
class MeshFormatException : Exception {

	/** Creates a new $(REF MeshFormatException) */
	this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable nextInChain = null) @nogc @safe pure nothrow {
		super(msg, file, line, nextInChain);
	}
}

/** Defines a 3D mesh */
class Mesh {
	/** Defines a 3D vertex */
	struct Vertex {
		/** The position of the vertex */
		Vector3 position;

		/** The normal vector of the vertex in local space */
		Vector3 normal;

		/** The UV coordinates of this vertex */
		Vector2 uv;
	}

	/** Defines a triangular face. Counter-clockwise vertices are seen as a front face */
	struct Face {
		/** The index of the 1st vertex of this face */
		ulong a;

		/** The index of the 2nd vertex of this face */
		ulong b;

		/** The index of the 3rd vertex of this face */
		ulong c;
	}

	private Vertex[] _vertices;
	private Face[] _faces;
	private bool dirty = true;
	private Object backendData;

	private static Mesh _cube;

	static this() {
		_cube = new Mesh([
			Vertex(Vector3(-0.5, +0.5, -0.5), Vector3(0, +1.0, 0), Vector2()),
			Vertex(Vector3(+0.5, +0.5, -0.5), Vector3(0, +1.0, 0), Vector2()),
			Vertex(Vector3(+0.5, +0.5, +0.5), Vector3(0, +1.0, 0), Vector2()),
			Vertex(Vector3(-0.5, +0.5, +0.5), Vector3(0, +1.0, 0), Vector2()),

			Vertex(Vector3(-0.5, -0.5, -0.5), Vector3(0, -1.0, 0), Vector2()),
			Vertex(Vector3(+0.5, -0.5, -0.5), Vector3(0, -1.0, 0), Vector2()),
			Vertex(Vector3(+0.5, -0.5, +0.5), Vector3(0, -1.0, 0), Vector2()),
			Vertex(Vector3(-0.5, -0.5, +0.5), Vector3(0, -1.0, 0), Vector2()),

			Vertex(Vector3(-0.5, -0.5, -0.5), Vector3(-1.0, 0, 0), Vector2()),
			Vertex(Vector3(-0.5, +0.5, -0.5), Vector3(-1.0, 0, 0), Vector2()),
			Vertex(Vector3(-0.5, +0.5, +0.5), Vector3(-1.0, 0, 0), Vector2()),
			Vertex(Vector3(-0.5, -0.5, +0.5), Vector3(-1.0, 0, 0), Vector2()),

			Vertex(Vector3(+0.5, -0.5, -0.5), Vector3(+1.0, 0, 0), Vector2()),
			Vertex(Vector3(+0.5, +0.5, -0.5), Vector3(+1.0, 0, 0), Vector2()),
			Vertex(Vector3(+0.5, +0.5, +0.5), Vector3(+1.0, 0, 0), Vector2()),
			Vertex(Vector3(+0.5, -0.5, +0.5), Vector3(+1.0, 0, 0), Vector2()),

			Vertex(Vector3(-0.5, -0.5, -0.5), Vector3(0, 0, -1.0), Vector2()),
			Vertex(Vector3(+0.5, -0.5, -0.5), Vector3(0, 0, -1.0), Vector2()),
			Vertex(Vector3(+0.5, +0.5, -0.5), Vector3(0, 0, -1.0), Vector2()),
			Vertex(Vector3(-0.5, +0.5, -0.5), Vector3(0, 0, -1.0), Vector2()),

			Vertex(Vector3(-0.5, -0.5, +0.5), Vector3(0, 0, +1.0), Vector2()),
			Vertex(Vector3(+0.5, -0.5, +0.5), Vector3(0, 0, +1.0), Vector2()),
			Vertex(Vector3(+0.5, +0.5, +0.5), Vector3(0, 0, +1.0), Vector2()),
			Vertex(Vector3(-0.5, +0.5, +0.5), Vector3(0, 0, +1.0), Vector2()),
		], [
			Face(2, 1, 0),
			Face(0, 3, 2),

			Face(4, 5, 6),
			Face(6, 7, 4),

			Face(8, 11, 10),
			Face(10, 9, 8),

			Face(14, 15, 12),
			Face(12, 13, 14),

			Face(18, 17, 16),
			Face(16, 19, 18),

			Face(20, 21, 22),
			Face(22, 23, 20),
		]);
	}

	/** Returns a flat-shaded 1x1x1 cube centered around the origin. The result is cached so this method may be called many times */
	static Mesh cube() { return _cube; }

	/** Constructs a $(REF Mesh) with the given vertices and faces */
	this(const(Vertex)[] vertices, const(Face)[] faces) {
		_vertices = vertices.dup;
		_faces = faces.dup;
	}

	/** The vertices of this $(REF Mesh) */
	const(Vertex)[] vertices() const @property { return _vertices; }

	/** The faces of this $(REF Mesh) */
	const(Face)[] faces() const @property { return _faces; }

	/** Modifies each vertex's normal to be the sum of the normals of all the vertex's faces */
	Mesh smooth() {
		Vector3[Vector3] normalSums;
		foreach (v; vertices) {
			if (v.position !in normalSums) {
				normalSums[v.position] = Vector3.init;
			}
		}
		foreach (f; faces) {
			Vertex a = vertices[f.a];
			Vertex b = vertices[f.b];
			Vertex c = vertices[f.c];
			Vector3 normal = (a.position - b.position).cross(a.position - c.position).unit;
			normalSums[a.position] += normal;
			normalSums[b.position] += normal;
			normalSums[c.position] += normal;
		}
		Vertex[] newVertices;
		foreach (v; vertices) {
			newVertices ~= Vertex(v.position, normalSums[v.position].unit, v.uv);
		}
		return new Mesh(newVertices, faces);
	}

	/** Decodes a binary .STL file from memory */
	static Mesh readStl(void[] source) {
		import std.exception : enforce;
		import std.bitmanip : littleEndianToNative;

		Vertex[] vertices;
		Face[] faces;

		enforce(source.length >= 84, new MeshFormatException("stl file must be at least 84 bytes long"));

		size_t numFaces = cast(size_t) littleEndianToNative!uint(cast(ubyte[4]) source[80 .. 84]);
		enum faceSize = 12 * 4 + 2;
		size_t expectedSize = numFaces * faceSize + 84;

		enforce(source.length == expectedSize, new MeshFormatException("stl file with " ~ numFaces.to!string ~ " faces is expected to be " ~ expectedSize.to!string ~ " bytes long; got file of " ~ source.length.to!string ~ " bytes"));

		foreach (i; 0 .. numFaces) {
			size_t offset = i * faceSize + 84;
			float[12] floats;
			foreach (j; 0 .. 12) {
				floats[j] = littleEndianToNative!float((cast(ubyte[]) source[offset + 4 * j .. offset + 4 * j + 4]).to!(ubyte[4]));
			}
			Vector3 normal = Vector3(floats[0], floats[1], floats[2]);
			Vector3 v1 = Vector3(floats[3], floats[4], floats[5]);
			Vector3 v2 = Vector3(floats[6], floats[7], floats[8]);
			Vector3 v3 = Vector3(floats[9], floats[10], floats[11]);
			normal = Vector3(normal.x, normal.z, -normal.y);
			v1 = Vector3(v1.x, v1.z, -v1.y);
			v2 = Vector3(v2.x, v2.z, -v2.y);
			v3 = Vector3(v3.x, v3.z, -v3.y);
			vertices ~= Vertex(v1, normal, Vector2.init);
			vertices ~= Vertex(v2, normal, Vector2.init);
			vertices ~= Vertex(v3, normal, Vector2.init);
			faces ~= Face(i * 3 + 0, i * 3 + 1, i * 3 + 2);
		}

		return new Mesh(vertices, faces);
	}

	/** Loads an .STL file into memory */
	static Mesh readStlFrom(string path) {
		import std.stdio : File, SEEK_END;

		File file = File(path, "rb");
		file.seek(0, SEEK_END);
		auto size = file.tell();
		file.rewind();
		void[] buffer = new void[size];
		file.rawRead(buffer);
		file.close();

		return readStl(buffer);
	}

}

/** Gets the current Unix timestamp, as in the number of seconds since midnight, January 1st, 1970. This may change with the system time, so don't rely on it being monotonic; use $(REF timestamp) for that. */
double unixTimestamp() {
	import std.datetime.systime : SysTime, Clock;
	import std.datetime.interval : Interval;
	import std.datetime.date : DateTime;
	import std.datetime.timezone : UTC;

	return Interval!SysTime(SysTime(DateTime(1970, 1, 1), UTC()), Clock.currTime)
		.length.total!"hnsecs" / 10_000_000.0;
}

import core.time : MonoTime;
private MonoTime start;

static this() {
	start = MonoTime.currTime;
}

/** Counts the number of seconds that have passed since the program started running. */
double timestamp() {
	return (MonoTime.currTime - start).total!"hnsecs" / 10_000_000.0;
}

/** Defines a 3D scene, with various attributes, bound to a certain OpenGL context */
final class Scene {

	private RefCounted!OpenGLBackend renderer;

	/** The total size of the viewport */
	Vector2 viewportSize;

	/** Shorthand for $(D this.viewportSize.x / this.viewportSize.y) */
	double aspect() const @property {
		return viewportSize.x / viewportSize.y;
	}

	/** The forward vector of the global directional light source */
	Vector3 lightDir = Vector3(-0.5, -1, -0.3);

	/** The color of the global directional light source */
	Vector3 lightColor = Vector3(1, 1, 1);

	/** The ambient light in the scene */
	Vector3 ambient = Vector3(1, 1, 1) * 0.05;

	private Matrix4 delegate() _projection;

	/** Recalculates the currently-set projection matrix */
	Matrix4 projection() const {
		return _projection();
	}

	/** Lazily sets the projection matrix. The value may be re-calculated every frame, so keep it speedy */
	void projection(Matrix4 delegate() value) {
		_projection = value;
	}

	/** The camera transform matrix */
	Matrix4 camera;

	this() {
		projection = () => Matrix4.perspective(70 * PI / 180, aspect, 0.1, 10_000.0);
		renderer = RefCounted!OpenGLBackend(OpenGLBackend(0));
	}

	/** Clears the destination rectangle with the given color */
	void clear(Vector4 color) {
		renderer.clear(this, color);
	}

	/** Renders the given mesh with the given parameters */
	void render(Mesh mesh, Matrix4 transform, Material material = null, Vector4 tint = Vector4(1, 1, 1, 1)) {
		renderer.render(this, mesh, transform, material, tint);
	}

}

final class Material {
	double specular = 0.5;
	double shininess = 32;
	Vector4 color = Vector4(1, 1, 1, 1);
}

private interface RenderingBackend {

	void clear(Scene ctx, Vector4 color);

	void render(Scene ctx, Mesh mesh, Matrix4 transform, Material material, Vector4 tint);

	void close();

}

private struct OpenGLBackend {

	static size_t glCount;
	static Object[] glResources; // TODO: FIXME: weak set

	static void loadGL() {
		if (gl is null) {
			bool success = .loadGL();
			if (!success) {
				throw new Exception("Could not load OpenGL"); // TODO: better error handling
			}
		}
		glCount++;
	}

	static void unloadGL() {
		glCount--;
		if (glCount == 0) {
			foreach (resource; glResources) {
				destroy(resource);
			}
			glResources = [];
			.unloadGL();
		}
	}

	ShaderProgram program;

	bool reallyConstructed = false;

	this(int dummy) {
		reallyConstructed = true;

		loadGL();

		program = new ShaderProgram([
			new Shader(gl.VERTEX_SHADER, q"(
				#version 330 core
				layout (location = 0) in vec3 aPos;
				layout (location = 1) in vec3 aNormal;
				layout (location = 2) in vec2 aUv;

				out vec3 Normal;
				out vec3 Pos;
				out vec2 Uv;

				uniform vec2 uViewport;
				uniform mat4 uProjection;
				uniform mat4 uModel;

				void main() {
					gl_Position = uProjection * uModel * vec4(aPos, 1.0);
					Pos = (uModel * vec4(aPos, 1.0)).xyz;
					Normal = mat3(transpose(inverse(uModel))) * aNormal; // TODO: calculate normal matrix on CPU
					Uv = aUv;
				}
			)"),
			new Shader(gl.FRAGMENT_SHADER, q"(
				#version 400 core
				out vec4 FragColor;

				uniform vec3 uLightDir;
				uniform vec3 uLightColor;
				uniform vec3 uLightAmbient;
				uniform vec4 uColor;
				uniform mat4 uCamera;
				uniform sampler2D uTexture;
				uniform bool uTextureEnabled;

				uniform float uShininess;
				uniform float uSpecular;
				uniform vec4 uMatColor;

				in vec3 Normal;
				in vec3 Pos;
				in vec2 Uv;

				float gamma = 2.2;

				vec4 gammaCorrect(vec4 color) {
					return vec4(pow(color.rgb, vec3(1.0 / gamma)), color.a);
				}

				vec4 gammaIncorrect(vec4 color) {
					return vec4(pow(color.rgb, vec3(gamma)), color.a);
				}

				void main() {
					vec3 lightDir = normalize(-uLightDir);
					vec3 normal = normalize(Normal);

					vec3 diffuse = uLightColor * max(dot(normal, lightDir), 0.);

					vec3 cameraPos = uCamera[3].xyz;
					vec3 viewDir = normalize(cameraPos - Pos);
					vec3 reflectDir = reflect(-lightDir, normal);
					float spec = pow(max(dot(viewDir, reflectDir), 0.), uShininess);
					vec3 specular = uSpecular * spec * uLightColor;

					vec4 c0 = uColor * uMatColor;
					vec4 c1 = vec4(0., 0., 0., 0.);
					if (uTextureEnabled) {
						c1 = texture(uTexture, Uv);
					}

					vec3 res = (uLightAmbient + diffuse + specular)
						* gammaIncorrect(mix(c0, c1, c1.a)).xyz;
					FragColor = gammaCorrect(vec4(res, uColor.w));
				}
			)"),
		]);
	}

	~this() {
		if (reallyConstructed) {
			unloadGL();
		}
	}

	void clear(Scene ctx, Vector4 color) {
		gl.clearColor(color.r, color.g, color.b, color.a);
		gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
		gl.enable(gl.DEPTH_TEST);
		gl.enable(gl.CULL_FACE);
	}

	private void updateMesh(Mesh mesh) {
		GLMesh backend = cast(GLMesh) mesh.backendData;
		if (backend is null) {
			mesh.backendData = new GLMesh(mesh, MeshAttrs.Position3D | MeshAttrs.Normal | MeshAttrs.UV);
			mesh.dirty = false;
		}
		else if (mesh.dirty) {
			backend.update(mesh);
			mesh.dirty = false;
		}
	}

	void render(Scene ctx, Mesh mesh, Matrix4 transform, Material material, Vector4 tint) {
		program.use();

		if (material is null) {
			program.set!"uSpecular"(0.5);
			program.set!"uShininess"(32.0);
			program.set!"uMatColor"(Vector4(1, 1, 1, 1));
		}
		else {
			program.set!"uSpecular"(material.specular);
			program.set!"uShininess"(material.shininess);
			program.set!"uMatColor"(material.color);
		}

		program.set!"uProjection"(ctx.projection * ctx.camera.inverse);
		program.set!"uViewport"(ctx.viewportSize);
		program.set!"uCamera"(ctx.camera);

		program.set!"uLightDir"(ctx.lightDir);
		program.set!"uLightColor"(ctx.lightColor);
		program.set!"uLightAmbient"(ctx.ambient);

		program.set!"uColor"(tint);
		program.set!"uModel"(transform);

		program.set!"uTextureEnabled"(false);

		updateMesh(mesh);
		GLMesh backend = cast(GLMesh) mesh.backendData;
		gl.bindVertexArray(backend.vao);
		gl.drawElements(gl.TRIANGLES, cast(gl.Sizei) backend.numFaces * 3, gl.UNSIGNED_INT, null);
	}

	class ShaderException : Exception {
		this(string msg, string file = __FILE__, size_t line = __LINE__, Throwable nextInChain = null) @nogc @safe pure nothrow {
			super(msg, file, line, nextInChain);
		}
	}

	class Shader {

		gl.UInt id;

		this(gl.Enum shaderType, string source) {
			id = gl.createShader(shaderType);
			
			auto length = cast(gl.Int) source.length;
			assert(cast(size_t) length == source.length);
			const(char)* ptr = source.ptr;
			gl.shaderSource(id, 1, &ptr, &length);
			gl.compileShader(id);

			gl.Int success;
			gl.getShaderiv(id, gl.COMPILE_STATUS, &success);

			debug {
				if (!success) {
					import core.stdc.string : strlen;

					gl.Char[] infoLog = new gl.Char[1024];
					gl.getShaderInfoLog(id, 1024, null, infoLog.ptr);
					throw new ShaderException(infoLog[0 .. strlen(infoLog.ptr)].idup);
				}
			}
			else {
				assert(success);
			}

			glResources ~= this;
		}

		~this() {
			gl.deleteShader(id);
		}

	}

	class ShaderProgram {
		import std.string : toStringz;

		gl.UInt id;

		@disable this();

		this(Shader[] shaders) {
			id = gl.createProgram();

			foreach (shader; shaders) {
				gl.attachShader(id, shader.id);
			}

			gl.linkProgram(id);

			gl.Int success;
			gl.getProgramiv(id, gl.LINK_STATUS, &success);

			debug {
				if (!success) {
					import core.stdc.string : strlen;

					gl.Char[] infoLog = new gl.Char[1024];
					gl.getShaderInfoLog(id, 1024, null, infoLog.ptr);
					throw new ShaderException(infoLog[0 .. strlen(infoLog.ptr)].idup);
				}
			}
			else {
				assert(success);
			}

			glResources ~= this;
		}

		~this() {
			gl.deleteProgram(id);
		}

		void use() {
			gl.useProgram(id);
		}

		private template setUniform(string uniform, T) {
			gl.Int loc = -1;
			T value;

			void setUniform(void function(gl.Int, T) setter)(T newValue) {
				bool setAlready = loc != -1;
				if (loc == -1) {
					loc = gl.getUniformLocation(id, toStringz(uniform));
				}
				if (!setAlready || value != newValue) {
					value = newValue;
					setter(loc, newValue);
				}
			}
		}

		void set(string uniform)(float value) {
			alias s = setUniform!(uniform, float);
			s!((gl.Int loc, float v) {
				gl.uniform1f(loc, cast(gl.Float) v);
			})(value);
		}

		void set(string uniform)(double value) {
			alias s = setUniform!(uniform, double);
			s!((gl.Int loc, double v) {
				gl.uniform1f(loc, cast(gl.Float) v);
			})(value);
		}

		void set(string uniform)(int value) {
			alias s = setUniform!(uniform, int);
			s!((gl.Int loc, int v) {
				gl.uniform1i(loc, cast(gl.Int) v);
			})(value);
		}

		void set(string uniform)(bool value) {
			set!uniform(value ? 1 : 0);
		}

		void set(string uniform)(Vector2 value) {
			alias s = setUniform!(uniform, Vector2);
			s!((gl.Int loc, Vector2 v) {
				gl.uniform2f(loc, cast(gl.Float) v.x, cast(gl.Float) v.y);
			})(value);
		}

		void set(string uniform)(Vector3 value) {
			alias s = setUniform!(uniform, Vector3);
			s!((gl.Int loc, Vector3 v) {
				gl.uniform3f(loc, cast(gl.Float) v.x, cast(gl.Float) v.y, cast(gl.Float) v.z);
			})(value);
		}

		void set(string uniform)(Vector4 value) {
			alias s = setUniform!(uniform, Vector4);
			s!((gl.Int loc, Vector4 v) {
				gl.uniform4f(loc, cast(gl.Float) v.x, cast(gl.Float) v.y, cast(gl.Float) v.z, cast(gl.Float) v.w);
			})(value);
		}

		void set(string uniform)(Matrix4 value) {
			alias s = setUniform!(uniform, Matrix4);
			s!((gl.Int loc, Matrix4 v) {
				gl.Float[16] matrixData;
				matrixData[0] = cast(gl.Float) v[0, 0];
				matrixData[1] = cast(gl.Float) v[1, 0];
				matrixData[2] = cast(gl.Float) v[2, 0];
				matrixData[3] = cast(gl.Float) v[3, 0];
				matrixData[4] = cast(gl.Float) v[0, 1];
				matrixData[5] = cast(gl.Float) v[1, 1];
				matrixData[6] = cast(gl.Float) v[2, 1];
				matrixData[7] = cast(gl.Float) v[3, 1];
				matrixData[8] = cast(gl.Float) v[0, 2];
				matrixData[9] = cast(gl.Float) v[1, 2];
				matrixData[10] = cast(gl.Float) v[2, 2];
				matrixData[11] = cast(gl.Float) v[3, 2];
				matrixData[12] = cast(gl.Float) v[0, 3];
				matrixData[13] = cast(gl.Float) v[1, 3];
				matrixData[14] = cast(gl.Float) v[2, 3];
				matrixData[15] = cast(gl.Float) v[3, 3];
				gl.uniformMatrix4fv(loc, 1, false, matrixData.ptr);
			})(value);
		}

	}

	enum MeshAttrs {
		None = 0,
		Position2D = 1,
		Position3D = 2,
		Normal = 4,
		UV = 8,
	}

	final class GLMesh {
		gl.UInt vbo;
		gl.UInt vao;
		gl.UInt ebo;
		size_t numFaces;
		MeshAttrs attrs;

		private size_t stride() {
			size_t result;
			if (attrs & MeshAttrs.Position2D) {
				result += 2;
			}
			else if (attrs & MeshAttrs.Position3D) {
				result += 3;
			}
			if (attrs & MeshAttrs.Normal) {
				result += 3;
			}
			if (attrs & MeshAttrs.UV) {
				result += 2;
			}
			return result;
		}

		this(Mesh mesh, MeshAttrs attrs) {
			assert((attrs & 3) != 3, "Position cannot be both 2D and 3D");

			this.attrs = attrs;

			gl.genBuffers(1, &vbo);
			gl.genBuffers(1, &ebo);
			gl.genVertexArrays(1, &vao);

			update(mesh);

			size_t pos;
			gl.UInt array;

			if (attrs & MeshAttrs.Position2D) {
				gl.vertexAttribPointer(array, 2, gl.FLOAT, gl.FALSE, cast(gl.Sizei)(stride * gl.Float.sizeof), cast(void*)(pos * gl.Float.sizeof));
				gl.enableVertexAttribArray(array);
				array += 1;
				pos += 2;
			}
			else if (attrs & MeshAttrs.Position3D) {
				gl.vertexAttribPointer(array, 3, gl.FLOAT, gl.FALSE, cast(gl.Sizei)(stride * gl.Float.sizeof), cast(void*)(pos * gl.Float.sizeof));
				gl.enableVertexAttribArray(array);
				array += 1;
				pos += 3;
			}
			if (attrs & MeshAttrs.Normal) {
				gl.vertexAttribPointer(array, 3, gl.FLOAT, gl.FALSE, cast(gl.Sizei)(stride * gl.Float.sizeof), cast(void*)(pos * gl.Float.sizeof));
				gl.enableVertexAttribArray(array);
				array += 1;
				pos += 3;
			}
			if (attrs & MeshAttrs.UV) {
				gl.vertexAttribPointer(array, 2, gl.FLOAT, gl.FALSE, cast(gl.Sizei)(stride * gl.Float.sizeof), cast(void*)(pos * gl.Float.sizeof));
				gl.enableVertexAttribArray(array);
				array += 1;
				pos += 2;
			}

			glResources ~= this;
		}

		~this() {
			gl.deleteBuffers(1, &vbo);
			gl.deleteBuffers(1, &ebo);
			gl.deleteVertexArrays(1, &vao);
		}

		void update(Mesh mesh) {
			numFaces = mesh.faces.length;

			gl.bindVertexArray(vao);

			gl.bindBuffer(gl.ARRAY_BUFFER, vbo);

			size_t stride = this.stride;
			gl.Float[] vertices = new gl.Float[mesh.vertices.length * stride];
			size_t j = 0;
			foreach (i; 0 .. mesh.vertices.length) {
				auto v = mesh.vertices[i];
				if (attrs & MeshAttrs.Position2D) {
					vertices[j++] = cast(gl.Float) v.position.x;
					vertices[j++] = cast(gl.Float) v.position.y;
				}
				else if (attrs & MeshAttrs.Position3D) {
					vertices[j++] = cast(gl.Float) v.position.x;
					vertices[j++] = cast(gl.Float) v.position.y;
					vertices[j++] = cast(gl.Float) v.position.z;
				}
				if (attrs & MeshAttrs.Normal) {
					vertices[j++] = cast(gl.Float) v.normal.x;
					vertices[j++] = cast(gl.Float) v.normal.y;
					vertices[j++] = cast(gl.Float) v.normal.z;
				}
				if (attrs & MeshAttrs.UV) {
					vertices[j++] = cast(gl.Float) v.uv.x;
					vertices[j++] = cast(gl.Float) v.uv.y;
				}
			}
			gl.bufferData(gl.ARRAY_BUFFER, gl.Float.sizeof * mesh.vertices.length * stride, vertices.ptr, gl.STATIC_DRAW); // TODO: check bufferData doc gen

			gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo);
			gl.UInt[] faces = new gl.UInt[mesh.faces.length * 3];
			foreach (i; 0 .. mesh.faces.length) {
				auto f = mesh.faces[i];
				faces[i * 3 + 0] = cast(gl.UInt) f.a;
				faces[i * 3 + 1] = cast(gl.UInt) f.b;
				faces[i * 3 + 2] = cast(gl.UInt) f.c;
			}
			gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, gl.UInt.sizeof * mesh.faces.length * 3, faces.ptr, gl.STATIC_DRAW);
		}
	}

}

// grep 'xwin' to find all cases of windowing library-specific code

static if (__traits(compiles, () { import arsd.simpledisplay; })) {
	private enum _UseSDPY = true;
	private enum _Windowing = true;
}

static if (_Windowing) {
	enum DisplayLibrary {
		SimpleDisplay,
	}

	// xwin
	static if (_UseSDPY) {
		import sdpy = arsd.simpledisplay;

		enum CurrentLibrary = DisplayLibrary.SimpleDisplay;

		private Nullable!KeyCode fromSdpyMouseButton(sdpy.MouseButton button) {
			switch (button) {
			case sdpy.MouseButton.left:
				return Nullable!KeyCode(KeyCode.LeftButton);
			case sdpy.MouseButton.middle:
				return Nullable!KeyCode(KeyCode.MiddleButton);
			case sdpy.MouseButton.right:
				return Nullable!KeyCode(KeyCode.RightButton);
			case sdpy.MouseButton.forwardButton:
				return Nullable!KeyCode(KeyCode.ForwardButton);
			case sdpy.MouseButton.backButton:
				return Nullable!KeyCode(KeyCode.BackButton);
			default:
				return Nullable!KeyCode();
			}
		}

		private KeyModifiers fromSdpyModifiers(sdpy.ModifierState state) {
			KeyModifiers result;
			if (state & sdpy.ModifierState.shift)
				result |= KeyModifiers.Shift;
			if (state & sdpy.ModifierState.ctrl)
				result |= KeyModifiers.Ctrl;
			if (state & sdpy.ModifierState.alt)
				result |= KeyModifiers.Alt;
			if (state & sdpy.ModifierState.windows)
				result |= KeyModifiers.Super;
			if (state & sdpy.ModifierState.capsLock)
				result |= KeyModifiers.CapsLock;
			if (state & sdpy.ModifierState.numLock)
				result |= KeyModifiers.NumLock;
			return result;
		}

		private Nullable!KeyCode fromSdpyKey(sdpy.Key key) {
			switch (key) {
			case sdpy.Key.Space: return Nullable!KeyCode(KeyCode.Space);
			case sdpy.Key.Apostrophe: return Nullable!KeyCode(KeyCode.Quote);
			case sdpy.Key.Comma: return Nullable!KeyCode(KeyCode.Comma);
			case sdpy.Key.Dash: return Nullable!KeyCode(KeyCode.Minus);
			case sdpy.Key.Period: return Nullable!KeyCode(KeyCode.Period);
			case sdpy.Key.Slash: return Nullable!KeyCode(KeyCode.Slash);
			case sdpy.Key.N0: return Nullable!KeyCode(KeyCode.D0);
			case sdpy.Key.N1: return Nullable!KeyCode(KeyCode.D1);
			case sdpy.Key.N2: return Nullable!KeyCode(KeyCode.D2);
			case sdpy.Key.N3: return Nullable!KeyCode(KeyCode.D3);
			case sdpy.Key.N4: return Nullable!KeyCode(KeyCode.D4);
			case sdpy.Key.N5: return Nullable!KeyCode(KeyCode.D5);
			case sdpy.Key.N6: return Nullable!KeyCode(KeyCode.D6);
			case sdpy.Key.N7: return Nullable!KeyCode(KeyCode.D7);
			case sdpy.Key.N8: return Nullable!KeyCode(KeyCode.D8);
			case sdpy.Key.N9: return Nullable!KeyCode(KeyCode.D9);
			case sdpy.Key.Semicolon: return Nullable!KeyCode(KeyCode.Semicolon);
			case sdpy.Key.Equals: return Nullable!KeyCode(KeyCode.Equals);
			case sdpy.Key.A: return Nullable!KeyCode(KeyCode.A);
			case sdpy.Key.B: return Nullable!KeyCode(KeyCode.B);
			case sdpy.Key.C: return Nullable!KeyCode(KeyCode.C);
			case sdpy.Key.D: return Nullable!KeyCode(KeyCode.D);
			case sdpy.Key.E: return Nullable!KeyCode(KeyCode.E);
			case sdpy.Key.F: return Nullable!KeyCode(KeyCode.F);
			case sdpy.Key.G: return Nullable!KeyCode(KeyCode.G);
			case sdpy.Key.H: return Nullable!KeyCode(KeyCode.H);
			case sdpy.Key.I: return Nullable!KeyCode(KeyCode.I);
			case sdpy.Key.J: return Nullable!KeyCode(KeyCode.J);
			case sdpy.Key.K: return Nullable!KeyCode(KeyCode.K);
			case sdpy.Key.L: return Nullable!KeyCode(KeyCode.L);
			case sdpy.Key.M: return Nullable!KeyCode(KeyCode.M);
			case sdpy.Key.N: return Nullable!KeyCode(KeyCode.N);
			case sdpy.Key.O: return Nullable!KeyCode(KeyCode.O);
			case sdpy.Key.P: return Nullable!KeyCode(KeyCode.P);
			case sdpy.Key.Q: return Nullable!KeyCode(KeyCode.Q);
			case sdpy.Key.R: return Nullable!KeyCode(KeyCode.R);
			case sdpy.Key.S: return Nullable!KeyCode(KeyCode.S);
			case sdpy.Key.T: return Nullable!KeyCode(KeyCode.T);
			case sdpy.Key.U: return Nullable!KeyCode(KeyCode.U);
			case sdpy.Key.V: return Nullable!KeyCode(KeyCode.V);
			case sdpy.Key.W: return Nullable!KeyCode(KeyCode.W);
			case sdpy.Key.X: return Nullable!KeyCode(KeyCode.X);
			case sdpy.Key.Y: return Nullable!KeyCode(KeyCode.Y);
			case sdpy.Key.Z: return Nullable!KeyCode(KeyCode.Z);
			case sdpy.Key.LeftBracket: return Nullable!KeyCode(KeyCode.LeftBracket);
			case sdpy.Key.Backslash: return Nullable!KeyCode(KeyCode.Backslash);
			case sdpy.Key.RightBracket: return Nullable!KeyCode(KeyCode.RightBracket);
			case sdpy.Key.Grave: return Nullable!KeyCode(KeyCode.Backtick); // TODO: check this one
			case sdpy.Key.Escape: return Nullable!KeyCode(KeyCode.Escape);
			case sdpy.Key.Enter: return Nullable!KeyCode(KeyCode.Enter);
			case sdpy.Key.Tab: return Nullable!KeyCode(KeyCode.Tab);
			case sdpy.Key.Backspace: return Nullable!KeyCode(KeyCode.Backspace);
			case sdpy.Key.Insert: return Nullable!KeyCode(KeyCode.Insert);
			case sdpy.Key.Delete: return Nullable!KeyCode(KeyCode.Delete);
			case sdpy.Key.Right: return Nullable!KeyCode(KeyCode.Right);
			case sdpy.Key.Left: return Nullable!KeyCode(KeyCode.Left);
			case sdpy.Key.Down: return Nullable!KeyCode(KeyCode.Down);
			case sdpy.Key.Up: return Nullable!KeyCode(KeyCode.Up);
			case sdpy.Key.PageUp: return Nullable!KeyCode(KeyCode.PageUp);
			case sdpy.Key.PageDown: return Nullable!KeyCode(KeyCode.PageDown);
			case sdpy.Key.Home: return Nullable!KeyCode(KeyCode.Home);
			case sdpy.Key.End: return Nullable!KeyCode(KeyCode.End);
			case sdpy.Key.CapsLock: return Nullable!KeyCode(KeyCode.CapsLock);
			case sdpy.Key.ScrollLock: return Nullable!KeyCode(KeyCode.ScrollLock);
			case sdpy.Key.NumLock: return Nullable!KeyCode(KeyCode.NumLock);
			case sdpy.Key.PrintScreen: return Nullable!KeyCode(KeyCode.PrintScreen);
			case sdpy.Key.Pause: return Nullable!KeyCode(KeyCode.Pause);
			case sdpy.Key.F1: return Nullable!KeyCode(KeyCode.F1);
			case sdpy.Key.F2: return Nullable!KeyCode(KeyCode.F2);
			case sdpy.Key.F3: return Nullable!KeyCode(KeyCode.F3);
			case sdpy.Key.F4: return Nullable!KeyCode(KeyCode.F4);
			case sdpy.Key.F5: return Nullable!KeyCode(KeyCode.F5);
			case sdpy.Key.F6: return Nullable!KeyCode(KeyCode.F6);
			case sdpy.Key.F7: return Nullable!KeyCode(KeyCode.F7);
			case sdpy.Key.F8: return Nullable!KeyCode(KeyCode.F8);
			case sdpy.Key.F9: return Nullable!KeyCode(KeyCode.F9);
			case sdpy.Key.F10: return Nullable!KeyCode(KeyCode.F10);
			case sdpy.Key.F11: return Nullable!KeyCode(KeyCode.F11);
			case sdpy.Key.F12: return Nullable!KeyCode(KeyCode.F12);
			// case sdpy.Key.F13: return Nullable!KeyCode(KeyCode.F13);
			// case sdpy.Key.F14: return Nullable!KeyCode(KeyCode.F14);
			// case sdpy.Key.F15: return Nullable!KeyCode(KeyCode.F15);
			// case sdpy.Key.F16: return Nullable!KeyCode(KeyCode.F16);
			// case sdpy.Key.F17: return Nullable!KeyCode(KeyCode.F17);
			// case sdpy.Key.F18: return Nullable!KeyCode(KeyCode.F18);
			// case sdpy.Key.F19: return Nullable!KeyCode(KeyCode.F19);
			// case sdpy.Key.F20: return Nullable!KeyCode(KeyCode.F20);
			// case sdpy.Key.F21: return Nullable!KeyCode(KeyCode.F21);
			// case sdpy.Key.F22: return Nullable!KeyCode(KeyCode.F22);
			// case sdpy.Key.F23: return Nullable!KeyCode(KeyCode.F23);
			// case sdpy.Key.F24: return Nullable!KeyCode(KeyCode.F24);
			// case sdpy.Key.F25: return Nullable!KeyCode(KeyCode.F25);
			case sdpy.Key.Pad0: return Nullable!KeyCode(KeyCode.Numpad0);
			case sdpy.Key.Pad1: return Nullable!KeyCode(KeyCode.Numpad1);
			case sdpy.Key.Pad2: return Nullable!KeyCode(KeyCode.Numpad2);
			case sdpy.Key.Pad3: return Nullable!KeyCode(KeyCode.Numpad3);
			case sdpy.Key.Pad4: return Nullable!KeyCode(KeyCode.Numpad4);
			case sdpy.Key.Pad5: return Nullable!KeyCode(KeyCode.Numpad5);
			case sdpy.Key.Pad6: return Nullable!KeyCode(KeyCode.Numpad6);
			case sdpy.Key.Pad7: return Nullable!KeyCode(KeyCode.Numpad7);
			case sdpy.Key.Pad8: return Nullable!KeyCode(KeyCode.Numpad8);
			case sdpy.Key.Pad9: return Nullable!KeyCode(KeyCode.Numpad9);
			case sdpy.Key.PadDot: return Nullable!KeyCode(KeyCode.NumpadPeriod);
			case sdpy.Key.Divide: return Nullable!KeyCode(KeyCode.NumpadSlash);
			case sdpy.Key.Multiply: return Nullable!KeyCode(KeyCode.NumpadMultiply);
			case sdpy.Key.Minus: return Nullable!KeyCode(KeyCode.NumpadMinus);
			case sdpy.Key.Plus: return Nullable!KeyCode(KeyCode.NumpadPlus);
			case sdpy.Key.PadEnter: return Nullable!KeyCode(KeyCode.NumpadEnter);
			// case sdpy.Key.PadEquals: return Nullable!KeyCode(KeyCode.NumpadEquals);
			case sdpy.Key.Shift: return Nullable!KeyCode(KeyCode.LeftShift);
			case sdpy.Key.Ctrl: return Nullable!KeyCode(KeyCode.LeftCtrl);
			case sdpy.Key.Alt: return Nullable!KeyCode(KeyCode.LeftAlt);
			case sdpy.Key.Windows: return Nullable!KeyCode(KeyCode.LeftSuper);
			case sdpy.Key.Shift_r: return Nullable!KeyCode(KeyCode.RightShift);
			case sdpy.Key.Ctrl_r: return Nullable!KeyCode(KeyCode.RightCtrl);
			case sdpy.Key.Alt_r: return Nullable!KeyCode(KeyCode.RightAlt);
			case sdpy.Key.Windows_r: return Nullable!KeyCode(KeyCode.RightSuper);
			case sdpy.Key.Menu: return Nullable!KeyCode(KeyCode.Menu);
			default: return Nullable!KeyCode();
			}
		}
	}
	else {
		static assert(0);
	}

	enum KeyModifiers {
		None = 0,
		Shift = 1, Ctrl = 2, Alt = 4, Super = 8,
		CapsLock = 16, NumLock = 32,
	}

	/** Defines a positional key code; that is, for the same physical key position, the key code will be equivalent on all keyboard layouts */
	enum KeyCode {
		/** Left mouse button */
		LeftButton,

		/** Middle mouse button */
		MiddleButton,

		/** Right mouse button */
		RightButton,

		/** Forward mouse button */
		ForwardButton,

		/** Back mouse button */
		BackButton,

		Space,
		Quote,
		Comma,
		Minus,
		Period,
		Slash,
		D0, D1, D2, D3, D4, D5, D6, D7, D8, D9,
		Semicolon,
		Equals,
		A, B, C, D, E, F, G, H, I, J, K, L, M,
		N, O, P, Q, R, S, T, U, V, W, X, Y, Z,
		LeftBracket,
		Backslash,
		RightBracket,
		Backtick,
		Escape,
		Enter,
		Tab,
		Backspace,
		Insert,
		Delete,
		Right,
		Left,
		Down,
		Up,
		PageUp,
		PageDown,
		Home,
		End,
		CapsLock,
		ScrollLock,
		NumLock,
		PrintScreen,
		Pause,
		F1, F2, F3, F4, F5, F6, F7, F8, F9, F10,
		F11, F12, F13, F14, F15, F16, F17, F18,
		F19, F20, F21, F22, F23, F24, F25,
		Numpad0, Numpad1, Numpad2,
		Numpad3, Numpad4, Numpad5,
		Numpad6, Numpad7, Numpad8,
		Numpad9, NumpadPeriod, NumpadSlash, NumpadMultiply,
		NumpadMinus, NumpadPlus, NumpadEnter, NumpadEquals,
		LeftShift, LeftCtrl, LeftAlt, LeftSuper,
		RightShift, RightCtrl, RightAlt, RightSuper,
		Menu,
	}

	/** Converts a $(REF KeyCode) to a human-readable representation */
	string displayKeyCode(KeyCode code) {
		import std.regex : ctRegex, replaceAll;

		if (code >= KeyCode.D0 && code <= KeyCode.D9) {
			return (code - cast(int) KeyCode.D0).to!string;
		}
		else if (code >= KeyCode.F1 && code <= KeyCode.F25) {
			return "F" ~ (code - cast(int) KeyCode.F1 + 1).to!string;
		}
		else {
			return code.to!string.replaceAll(ctRegex!r"([A-Z]|\d+)", " $1")[1 .. $];
		}
	}

	unittest {
		assert(displayKeyCode(KeyCode.LeftAlt) == "Left Alt");
		assert(displayKeyCode(KeyCode.D5) == "5");
		assert(displayKeyCode(KeyCode.Numpad5) == "Numpad 5");
		assert(displayKeyCode(KeyCode.F24) == "F24");
		assert(displayKeyCode(KeyCode.NumpadPeriod) == "Numpad Period");
		assert(displayKeyCode(KeyCode.B) == "B");
		assert(displayKeyCode(KeyCode.Backtick) == "Backtick");
	}

	/**

	A wrapper around a windowing library (arsd.simpledisplay) that does some convenient things for game development, specifically. It is `alias this`-ed with $(REF GameWindow.scene).

	*/
	final class GameWindow {

		// xwin
		static if (_UseSDPY) {
			private sdpy.SimpleWindow win;
		}
		else {
			static assert(0);
		}

		/** The scene that is bound to this window's context */
		Scene scene;

		alias scene this;

		/** The time step for the game's main loop */
		double timeStep = 1.0 / 60;

		/** After this many seconds, if there are still ticks that have not been processed, they will be dropped */
		double dropTicksAfter = 0.5;

		this(int width = 640, int height = 480, string title = "D Game", bool resizable = true) {
			// xwin
			static if (_UseSDPY) {
				sdpy.setOpenGLContextVersion(3, 3);
				sdpy.openGLContextCompatible = false;
				win = new sdpy.SimpleWindow(width, height, title, sdpy.OpenGlOptions.yes, resizable ? sdpy.Resizability.allowResizing : sdpy.Resizability.fixedSize);
				win.visibleForTheFirstTime = {
					win.setAsCurrentOpenGlContext;
					scene = new Scene;
					assert(_run, "null passed into GameWindow.run");
					_run(this);
				};
				win.redrawOpenGlScene = {
					gl.viewport(0, 0, win.width, win.height);
					viewportSize = Vector2(win.width, win.height);
					frameTimes ~= timestamp;
					_fps = computeFPS;
					if (onRender) onRender();
				};
			}
			else {
				static assert(0);
			}
		}

		private double[] frameTimes;

		private double _fps;

		/** Gets the latest FPS value for this window */
		double fps() const @property { return _fps; }

		private double computeFPS() {
			double ago = timestamp - 1;
			int count = 0;
			size_t i = frameTimes.length;
			if (i == 0) return 0; else i -= 1;
			while (i >= 1 && frameTimes[i] > ago) {
				count += 1;
				i -= 1;
			}
			auto result = count / (timestamp - frameTimes[i]);
			frameTimes = frameTimes[i .. $];
			return result;
		}

		/** Sets the title of the window */
		void title(string value) @property {
			// xwin
			static if (_UseSDPY) {
				win.title = value;
			}
			else {
				static assert(0);
			}
		}

		/** Gets the title of the window */
		string title() const @property {
			// xwin
			static if (_UseSDPY) {
				return (cast(sdpy.SimpleWindow) win).title;
			}
			else {
				static assert(0);
			}
		}

		private bool[KeyCode] keysDown;

		/** Checks if the given key is down */
		bool isKeyDown(KeyCode key) const {
			return (key in keysDown) != null;
		}

		/** This method is called when any ticks are dropped, with the parameter being the amount of time, in seconds, that is being dropped */
		void delegate(double) onDroppedTicks;

		/** This method is called every tick */
		void delegate() onTick;

		/** This method is called whenever the window renders. Avoid any game logic in here, game logic should preferably go into $(REF GameWindow.onTick). */
		void delegate() onRender;

		/** This method is called whenever a key or mouse button is pressed */
		void delegate(KeyCode, KeyModifiers) onKeyPress;

		/** This method is called whenever a key or mouse button is released */
		void delegate(KeyCode, KeyModifiers) onKeyRelease;

		/**

		This method is called when the scroll wheel is rotated. When rotated up, the value will be positive; down will be negative. On notched scroll wheels, the value will be an integer, representing the number of notches that were scrolled in the given direction.

		I have no idea what happens on smooth scroll wheels, if anyone has the hardware to test this, please contact me: brianush1@outlook.com

		*/
		void delegate(double) onScroll;

		/** This method is called whenever the mouse moves, with the old position and new position, respectively, passed as arguments */
		void delegate(Vector2, Vector2) onMouseMove;

		private void delegate(GameWindow) _run;

		/** Runs the $(REF GameWindow) */
		void run(void delegate(GameWindow) handler) {
			_run = handler;
			eventLoop;
		}

		private Vector2 _cursorPos;

		/** Gets the latest cursor position */
		Vector2 cursorPos() const @property {
			return _cursorPos;
		}

		private Vector2 lockStart;
		private bool lockedCursor;

		/** Hides and locks the cursor to the window; the cursor position will continue updating, but it will not be bounded to the size of the window any longer */
		void lockCursor() {
			if (lockedCursor)
				return;
			lockedCursor = true;
			lockStart = _cursorPos;
			win.hideCursor();
			win.grabInput(true, true, true);
		}

		/** Unlocks the cursor */
		void unlockCursor() {
			if (!lockedCursor)
				return;
			lockedCursor = false;
			win.warpMouse(cast(int) lockStart.x, cast(int) lockStart.y);
			win.showCursor();
			win.releaseInputGrab();
		}

		private void eventLoop() {
			double prev = 0;
			double lag = 0;
			win.eventLoop(1, {
				double now = timestamp;
				lag += now - prev;
				prev = now;
				assert(timeStep > 0, "Time step must be above 0");
				if (lag > dropTicksAfter) {
					if (onDroppedTicks) onDroppedTicks(lag);
					lag = 0;
				}
				while (lag >= timeStep) {
					lag -= timeStep;
					if (onTick) onTick();
				}
				win.redrawOpenGlSceneNow;
			}, delegate(sdpy.KeyEvent ev) {
				auto maybeKey = ev.key.fromSdpyKey;
				if (maybeKey.isNull)
					return;
				auto key = maybeKey.get;
				if (ev.pressed) {
					keysDown[key] = true;
				}
				else {
					keysDown.remove(key);
				}
				auto modifiers = fromSdpyModifiers(cast(sdpy.ModifierState) ev.modifierState);
				if (ev.pressed) {
					if (onKeyPress) onKeyPress(key, modifiers);
				}
				else {
					if (onKeyRelease) onKeyRelease(key, modifiers);
				}
			}, delegate(sdpy.MouseEvent ev) {
				if (ev.type == sdpy.MouseEventType.motion) {

					Vector2 pos = Vector2(ev.x, ev.y);

					Vector2 prevPos = _cursorPos;

					if (lockedCursor) {
						Vector2 delta = pos - Vector2(win.width / 2, win.height / 2);

						_cursorPos += delta;

						win.warpMouse(win.width / 2, win.height / 2);
					}
					else {
						_cursorPos = pos;
					}

					if (onMouseMove) onMouseMove(prevPos, _cursorPos);
				}
				else {
					if (ev.type == sdpy.MouseEventType.buttonPressed) { // TODO: smooth scroll wheels?
						if (ev.button == sdpy.MouseButton.wheelUp) {
							if (onScroll) onScroll(1);
							return;
						}
						else if (ev.button == sdpy.MouseButton.wheelDown) {
							if (onScroll) onScroll(-1);
							return;
						}
					}
					auto button = fromSdpyMouseButton(ev.button);
					if (button.isNull)
						return;
					auto modifiers = fromSdpyModifiers(cast(sdpy.ModifierState) ev.modifierState);
					if (ev.type == sdpy.MouseEventType.buttonPressed) {
						if (onKeyPress) onKeyPress(button.get, modifiers);
					}
					else {
						if (onKeyRelease) onKeyRelease(button.get, modifiers);
					}
				}
			});
		}

	}
}
