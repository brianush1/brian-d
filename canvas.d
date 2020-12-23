module brian.canvas;
static assert(__traits(compiles, () {
	import brian.gl;
}), "brian.canvas depends on: brian.gl");
import brian.gl;
import std.conv;
import std.math;

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

	/** Applies the given operator onto each component in the vector and the given value */
	Vector2 opBinaryRight(string op)(double other) const {
		return mixin("Vector2(other" ~ op ~ "x, other" ~ op ~ "y)");
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

	Vector2 lerp(Vector2 other, double alpha) const {
		return this * alpha + other * (1 - alpha);
	}

}

/** A 3x3 transformation matrix */
struct Matrix3 {
	private double[3][3] m = [[1, 0, 0], [0, 1, 0], [0, 0, 1]];

	/** Creates a translation matrix using the given vector as its translation component */
	this(double x, double y) {
		m[0][0] = 1;
		m[0][1] = 0;
		m[0][2] = x;
		m[1][0] = 0;
		m[1][1] = 1;
		m[1][2] = y;
		m[2][0] = 0;
		m[2][1] = 0;
		m[2][2] = 1;
	}

	/** Creates a translation matrix using the given vector as its translation component */
	this(Vector2 vec) {
		this(vec.x, vec.y);
	}

	/** Creates a matrix from the given components, given in row-major order */
	this(double[3][3] m) {
		this.m = m;
	}

	/** The component at the given row, column of this matrix */
	double opIndex(size_t r, size_t c) const { return m[r][c]; }

	/** The X component of the translation vector of this matrix */
	double x() const @property { return m[0][2]; }

	/** The Y component of the translation vector of this matrix */
	double y() const @property { return m[1][2]; }

	/** The translation component of this matrix */
	Vector2 translation() const {
		return Vector2(x, y);
	}

	/** Creates a copy of the matrix and modifies the translation component */
	Matrix3 withTranslation(Vector2 value) const {
		Matrix3 res = this;
		res.m[0][2] = value.x;
		res.m[1][2] = value.y;
		return res;
	}

	/** Creates a copy of the matrix with the translation component removed */
	Matrix3 withoutTranslation() const {
		return withTranslation(Vector2.init);
	}

	/** The scale component of this matrix */
	Vector2 scale() const {
		return Vector2(m[0][0], m[1][1]);
	}

	/** Creates a copy of the matrix and modifies the scale component */
	Matrix3 withScale(Vector2 value) const {
		Matrix3 res = this;
		res.m[0][0] = value.x;
		res.m[1][1] = value.y;
		return res;
	}

	/** Creates a copy of the matrix with the scale component removed */
	Matrix3 withoutScale() const {
		return withScale(Vector2.init);
	}

	/**

	Creates a new rotation matrix created from the given rotation angle, in radians

	Params:
	theta = The angle to use in creating the matrix

	*/
	static Matrix3 angles(double theta) {
		return Matrix3([
			[cos(theta), -sin(theta), 0.0],
			[sin(theta), cos(theta), 0.0],
			[0.0, 0.0, 1.0],
		]);
	}

	/**

	Creates a new scale matrix with the given components.

	Params:
	x = The X-component scale to use in creating the matrix
	y = The Y-component scale to use in creating the matrix

	*/
	static Matrix3 scale(double x, double y) {
		return Matrix3([
			[x, 0, 0],
			[0, y, 0],
			[0, 0, 1.0],
		]);
	}

	/**

	Creates a new scale matrix.

	Params:
	value = The amount to scale by

	*/
	static Matrix3 scale(Vector2 value) {
		return scale(value.x, value.y);
	}

	void opOpAssign(string op)(const Matrix3 other) if (op == "*") {
		mixin("this = this ", op, " other;");
	}

	/** Computes the translation component of the product of the matrix and the translation matrix of the given vector */
	Vector2 opBinary(string op)(Vector2 other) const if (op == "*") {
		return (this * Matrix3(other)).translation;
	}

	/** Computes the product of this and the given matrix */
	Matrix3 opBinary(string op)(Matrix3 other) const if (op == "*") {
		double[3][3] M;

		M[0][0] = other.m[0][0] * m[0][0] + other.m[1][0] * m[0][1] + other.m[2][0] * m[0][2];
		M[1][0] = other.m[0][0] * m[1][0] + other.m[1][0] * m[1][1] + other.m[2][0] * m[1][2];
		M[2][0] = other.m[0][0] * m[2][0] + other.m[1][0] * m[2][1] + other.m[2][0] * m[2][2];
		M[0][1] = other.m[0][1] * m[0][0] + other.m[1][1] * m[0][1] + other.m[2][1] * m[0][2];
		M[1][1] = other.m[0][1] * m[1][0] + other.m[1][1] * m[1][1] + other.m[2][1] * m[1][2];
		M[2][1] = other.m[0][1] * m[2][0] + other.m[1][1] * m[2][1] + other.m[2][1] * m[2][2];
		M[0][2] = other.m[0][2] * m[0][0] + other.m[1][2] * m[0][1] + other.m[2][2] * m[0][2];
		M[1][2] = other.m[0][2] * m[1][0] + other.m[1][2] * m[1][1] + other.m[2][2] * m[1][2];
		M[2][2] = other.m[0][2] * m[2][0] + other.m[1][2] * m[2][1] + other.m[2][2] * m[2][2];

		return Matrix3(M);
	}

	string toString() const {
		return "(" ~ m[0].to!string ~ "\n" ~ m[1].to!string ~ "\n" ~ m[2].to!string ~ ")";
	}

}

/** An exception thrown when invalid hex is passed into $(D Color)'s constructor */
class HexFormatException : Exception {

	/** The hex string that was passed in and invalid */
	string culprit;

	/** Creates a new $(REF HexFormatException) */
	this(string msg, string culprit, string file = __FILE__, size_t line = __LINE__, Throwable nextInChain = null) @nogc @safe pure nothrow {
		super(msg, file, line, nextInChain);
		this.culprit = culprit;
	}
}

struct Color {
	double[4] rgba = [0, 0, 0, 0];

	ref r() inout @property { return rgba[0]; }
	ref g() inout @property { return rgba[1]; }
	ref b() inout @property { return rgba[2]; }
	ref a() inout @property { return rgba[3]; }

	this(double r, double g, double b, double a = 1) {
		this.r = r;
		this.g = g;
		this.b = b;
		this.a = a;
	}

	this(string hex) {
		if (hex.length > 0 && hex[0] == '#') {
			hex = hex[1 .. $];
		}

		try {
			if (hex.length == 3) {
				int a = hex[0 .. 1].to!int(16);
				int b = hex[1 .. 2].to!int(16);
				int c = hex[2 .. 3].to!int(16);
				this(a * 17 / 255.0, b * 17 / 255.0, c * 17 / 255.0);
				return;
			}
			else if (hex.length == 6) {
				int a = hex[0 .. 2].to!int(16);
				int b = hex[2 .. 4].to!int(16);
				int c = hex[4 .. 6].to!int(16);
				this(a / 255.0, b / 255.0, c / 255.0);
				return;
			}
			else if (hex.length == 4) {
				int a = hex[0 .. 1].to!int(16);
				int b = hex[1 .. 2].to!int(16);
				int c = hex[2 .. 3].to!int(16);
				int d = hex[3 .. 4].to!int(16);
				this(a * 17 / 255.0, b * 17 / 255.0, c * 17 / 255.0, d * 17 / 255.0);
				return;
			}
			else if (hex.length == 8) {
				int a = hex[0 .. 2].to!int(16);
				int b = hex[2 .. 4].to!int(16);
				int c = hex[4 .. 6].to!int(16);
				int d = hex[6 .. 8].to!int(16);
				this(a / 255.0, b / 255.0, c / 255.0, d / 255.0);
				return;
			}
			else {
				throw new HexFormatException("invalid hex color", hex);
			}
		}
		catch (ConvException) {
			throw new HexFormatException("invalid hex color", hex);
		}

		assert(0);
	}

}

enum Antialias {
	/** Perform multisample anti-aliasing or similar */
	Smooth,

	/** Perform subpixel anti-aliasing if supported;
	may be equivalent to Antialias.Smooth on some platforms */
	Subpixel,

	/** Perform no anti-aliasing */
	None,
}

enum BlendOp {
	/** The object is drawn as expected */
	Normal,

	/** The object is drawn as if nothing else were below */
	// Overwrite, // TODO: implement this
}

struct RenderOptions {
	Antialias antialias;
	BlendOp blend;
}

enum Join {
	Miter,
	Bevel,
	Round,
}

enum Cap {
	Square,
	Butt,
	Round,
}

struct StrokeOptions {
	double width = 1;
	Join join;
	Cap cap;

	RenderOptions render;
	alias render this;
}

enum FillRule {
	EvenOdd,
	//Nonzero, // TODO: implement this
}

struct FillOptions {
	FillRule rule;

	RenderOptions render;
	alias render this;
}

Vector2[4] quadToCubic(Vector2[3] curve) {
	Vector2 from = curve[0];
	Vector2 control = curve[1];
	Vector2 to = curve[2];
	return [
		from,
		from + 2/3.0 * (control - from),
		to + 2/3.0 * (control - to),
		to,
	];
}

struct Subpath {
	Vector2 start;
	Vector2[3][] curves;
	bool closed = false;
}

final class Path {

	private Vector2 at;
	private Subpath[] _subpaths;
	private bool editingSubpath = false;
	private bool dirty = true; // TOOD: check if this works when the same path is used in two different contexts; also check in ez3d

	Vector2 cursor() const @property {
		return at;
	}

	const(Subpath)[] subpaths() const {
		return _subpaths;
	}

	// Factory methods:

	static Path fromRectangle(double x, double y, double w, double h) {
		return fromRectangle(Vector2(x, y), Vector2(w, h));
	}

	static Path fromRectangle(Vector2 position, Vector2 size) {
		Path result = new Path;
		result.rectangle(position, size);
		return result;
	}

	static Path fromEllipse(double x, double y, double w, double h) {
		return fromEllipse(Vector2(x, y), Vector2(w, h));
	}

	static Path fromEllipse(Vector2 position, Vector2 size) {
		Path result = new Path;
		result.ellipse(position, size);
		return result;
	}

	static Path fromLine(double x1, double y1, double x2, double y2) {
		return fromLine(Vector2(x1, y1), Vector2(x2, y2));
	}

	static Path fromLine(Vector2 from, Vector2 to) {
		Path result = new Path;
		result.line(from, to);
		return result;
	}

	// Modifying methods:

	void close() {
		if (editingSubpath) {
			_subpaths[$ - 1].closed = true;
			editingSubpath = false;
			dirty = true;
		}
	}

	/** Stop editing the current subpath while leaving it unclosed */
	void leave() {
		editingSubpath = false;
	}

	void moveTo(double x, double y) { moveTo(Vector2(x, y)); }

	void moveTo(Vector2 point) {
		editingSubpath = false;
		at = point;
	}

	void bezierCurveTo(double c1x, double c1y,
			double c2x, double c2y, double x, double y) {
		bezierCurveTo(Vector2(c1x, c1y), Vector2(c2x, c2y), Vector2(x, y));
	}

	void bezierCurveTo(Vector2 c1, Vector2 c2, Vector2 point) {
		if (!editingSubpath) {
			Subpath subpath;
			subpath.start = at;
			subpath.curves = [[c1, c2, point]];
			_subpaths ~= subpath;
			editingSubpath = true;
		}
		else {
			_subpaths[$ - 1].curves ~= [c1, c2, point];
		}
		at = point;
		dirty = true;
	}

	void lineTo(double x, double y) { lineTo(Vector2(x, y)); }

	void lineTo(Vector2 point) {
		bezierCurveTo(at, point, point);
	}

	void clear() {
		at = Vector2(0, 0);
		_subpaths = [];
		editingSubpath = false;
		dirty = true;
	}

	void rectangle(double x, double y, double w, double h) {
		rectangle(Vector2(x, y), Vector2(w, h));
	}

	void rectangle(Vector2 position, Vector2 size) {
		moveTo(position);
		lineTo(position + size * Vector2(1, 0));
		lineTo(position + size * Vector2(1, 1));
		lineTo(position + size * Vector2(0, 1));
		close();
	}

	void ellipse(Vector2 position, Vector2 size) {
		ellipse(position.tupleof, size.tupleof);
	}

	void ellipse(double x, double y, double w, double h) {
		import std.math : sqrt;

		// TODO: allow to input any arbitrary number of control points for higher precision
		// Magic number taken from https://stackoverflow.com/questions/1734745/how-to-create-circle-with-b%C3%A9zier-curves
		const magic = 4.0 * (sqrt(2.0) - 1.0) / 3.0 / 2;
		const cx = x + w / 2;
		const cy = y + h / 2;
		moveTo(x + w, cy);
		bezierCurveTo(
			x + w, cy - magic * h,
			cx + magic * w, y,
			cx, y
		);
		bezierCurveTo(
			cx - magic * w, y,
			x, cy - magic * h,
			x, cy
		);
		bezierCurveTo(
			x, cy + magic * h,
			cx - magic * w, y + h,
			cx, y + h,
		);
		bezierCurveTo(
			cx + magic * w, y + h,
			x + w, cy + magic * h,
			x + w, cy,
		);
		close();
	}

	void line(double x1, double y1, double x2, double y2) {
		line(Vector2(x1, y1), Vector2(x2, y2));
	}

	void line(Vector2 from, Vector2 to) {
		moveTo(from);
		lineTo(to);
		leave();
	}

	// Copying methods:

	Path clone() const {
		Path result = new Path;
		result.at = at;
		foreach (subpath; subpaths) {
			Subpath newSubpath;
			newSubpath.start = subpath.start;
			newSubpath.curves = subpath.curves.dup;
			newSubpath.closed = subpath.closed;
			result._subpaths ~= newSubpath;
		}
		result.editingSubpath = editingSubpath;
		return result;
	}

	Path flatten() const {
		Path result = new Path;
		foreach (subpath; subpaths) {
			result.moveTo(subpath.start);
			Vector2 curr = subpath.start;
			foreach (curve; subpath.curves) {
				Vector2 from = curr;
				Vector2 to = curve[2];
				Vector2 c1 = curve[0];
				Vector2 c2 = curve[1];
				double approxLength = ((from - c1).magnitude + (c1 - c2).magnitude + (c2 - to).magnitude) / 12;
				size_t numSegs = cast(int) sqrt(100 + approxLength * approxLength);
				// size_t numSegs = 8;
				foreach_reverse (i; 0 .. numSegs) { // TODO: figure out why I need to reverse here; it works, but why???
					double alpha = (i + 1) / cast(double) numSegs;
					Vector2 q0 = from.lerp(c1, alpha);
					Vector2 q1 = c1.lerp(c2, alpha);
					Vector2 q2 = c2.lerp(to, alpha);
					Vector2 r0 = q0.lerp(q1, alpha);
					Vector2 r1 = q1.lerp(q2, alpha);
					Vector2 p = r0.lerp(r1, alpha);
					result.lineTo(p);
				}
				curr = to;
			}
			if (subpath.closed) {
				result.close();
			}
			else {
				result.leave();
			}
		}
		return result;
	}

	// Path stroke(Args...)(Args args) const {
	// 	Vector2 rotate(Vector2 vec) {
	// 		return Vector2(-vec.y, vec.x);
	// 	}

	// 	Vector2 intersect(Vector2[2] line1, Vector2[2] line2) {
	// 		double x1 = line1[0].x;
	// 		double y1 = line1[0].y;
	// 		double x2 = line1[1].x;
	// 		double y2 = line1[1].y;
	// 		double x3 = line2[0].x;
	// 		double y3 = line2[0].y;
	// 		double x4 = line2[1].x;
	// 		double y4 = line2[1].y;
	// 		return Vector2(
	// 			((x1 * y2 - y1 * x2) * (x3 - x4) - (x1 - x2) * (x3 * y4 - y3 * x4))
	// 			/ ((x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)),
	// 			((x1 * y2 - y1 * x2) * (y3 - y4) - (y1 - y2) * (x3 * y4 - y3 * x4))
	// 			/ ((x1 - x2) * (y3 - y4) - (y1 - y2) * (x3 - x4)),
	// 		);
	// 	}

	// 	auto options = StrokeOptions(args);
	// 	Path result = new Path;
	// 	foreach (subpath; subpaths) {
	// 		Vector2 curr = subpath.start;
	// 		foreach (i; 0 .. subpath.curves.length) {
	// 			auto curve1 = subpath.curves[i];
	// 			auto curve2 = i + 1 == subpath.curves.length ? curve1
	// 				: subpath.curves[i + 1];
	// 			Vector2 from = curr;
	// 			curr = curve1[2];
	// 			Vector2 normal1 = rotate((curve1[2] - from).unit);
	// 			Vector2 normal2 = rotate((curve2[2] - curve1[2]).unit);
	// 			Vector2[2] line1 = [
	// 				from + normal1 * options.width,
	// 				curve1[2] + normal1 * options.width,
	// 			];
	// 			Vector2[2] line2 = [
	// 				curve1[2] + normal2 * options.width,
	// 				curve2[2] + normal2 * options.width,
	// 			];
	// 			Vector2 delta1 = (line1[1] - line1[0]).unit;
	// 			Vector2 delta2 = (line2[1] - line2[0]).unit;
	// 			if (i == 0) {
	// 				result.moveTo(line1[0]);
	// 			}
	// 			if (i + 1 == subpath.curves.length
	// 					|| (delta1 - delta2).magnitude < 1e-6) {
	// 				// parallel
	// 				result.lineTo(line1[1]);
	// 			}
	// 			else {
	// 				result.lineTo(intersect(line1, line2));
	// 			}
	// 		}
	// 	}
	// 	return result;
	// }

}

final class Canvas {

	Vector2 size;

	ref inout(double) width() inout @property { return size.x; }
	ref inout(double) height() inout @property { return size.y; }

	private Path rect;

	this() {
		loadGL();

		rect = Path.fromRectangle(0, 0, 1, 1);
		program = new ShaderProgram([
			new Shader(gl.VERTEX_SHADER, q"(
				#version 330 core
				layout (location = 0) in vec2 aPos;
				layout (location = 2) in vec2 aUv;

				out vec2 Uv;

				uniform mat3 uTransform;
				uniform vec2 uViewport;

				void main() {
					vec2 pos = (uTransform * vec3(aPos, 1.0)).xy;
					pos = vec2(pos.x, -pos.y);
					pos /= uViewport / 2.0;
					pos += vec2(-1.0, 1.0);

					gl_Position = vec4(pos, 0.0, 1.0);
					Uv = aUv;
				}
			)"),
			new Shader(gl.FRAGMENT_SHADER, q"(
				#version 400 core
				out vec4 FragColor;

				uniform vec4 uColor;

				in vec2 Uv;

				void main() {
					FragColor = uColor;
				}
			)"),
		]);
	}

	~this() {
		foreach (resource; glResources) {
			destroy(resource);
		}
		unloadGL();
	}

	void begin(Color color) {
		begin();
		gl.clearColor(color.r, color.g, color.b, 1.0);
		gl.clear(gl.COLOR_BUFFER_BIT);
	}

	void begin() {
		gl.clear(gl.STENCIL_BUFFER_BIT);
		gl.disable(gl.DEPTH_TEST);
		gl.disable(gl.CULL_FACE);
		gl.enable(gl.BLEND);
		gl.enable(gl.STENCIL_TEST);
		gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
		gl.stencilMask(0xFF);
	}

	void fill(Path path, Color color, Matrix3 transform = Matrix3.init, FillOptions options = FillOptions.init) {
		program.use();

		if (options.antialias == Antialias.None) {
			gl.disable(gl.MULTISAMPLE);
		}
		else {
			gl.enable(gl.MULTISAMPLE);
		}

		program.set!"uViewport"(size);
		program.set!"uTransform"(transform);
		program.set!"uColor"(color);

		gl.stencilOp(gl.INVERT, gl.INVERT, gl.INVERT);
		gl.stencilFunc(gl.NEVER, 0xFF, 0xFF);

		GLMesh backend = getMesh(path);
		gl.bindVertexArray(backend.vao);
		gl.drawElements(gl.TRIANGLES, cast(gl.Sizei) backend.numFaces * 3, gl.UNSIGNED_INT, null);

		gl.stencilOp(gl.ZERO, gl.ZERO, gl.ZERO);
		gl.stencilFunc(gl.EQUAL, 0xFF, 0xFF);

		program.set!"uViewport"(Vector2(1, 1));
		program.set!"uTransform"(Matrix3.init);

		GLMesh wholeScreen = getMesh(rect);
		gl.bindVertexArray(wholeScreen.vao);
		gl.drawElements(gl.TRIANGLES, cast(gl.Sizei) wholeScreen.numFaces * 3, gl.UNSIGNED_INT, null);
	}

private:

	ShaderProgram program;

	Object[] glResources; // TODO: weak set
	GLMesh[Path] meshes; // TODO: weak map

	GLMesh getMesh(Path path) {
		GLMesh.Vertex[] vertices;
		GLMesh.Face[] faces;
		if (path !in meshes || path.dirty) {
			foreach (subpath; path.subpaths) {
				Vector2 at = subpath.start;
				foreach (curve; subpath.curves) {
					Vector2 to = curve[2];
					vertices ~= GLMesh.Vertex(Vector2(0, 0), Vector2());
					vertices ~= GLMesh.Vertex(at, Vector2());
					vertices ~= GLMesh.Vertex(to, Vector2());
					at = to;
				}
				vertices ~= GLMesh.Vertex(Vector2(0, 0), Vector2());
				vertices ~= GLMesh.Vertex(at, Vector2());
				vertices ~= GLMesh.Vertex(subpath.start, Vector2());
			}
		}
		for (ulong i = 0; i < vertices.length; i += 3) {
			faces ~= GLMesh.Face(i, i + 1, i + 2);
		}
		if (path !in meshes) {
			meshes[path] = new GLMesh(GLMesh.Mesh(vertices, faces), MeshAttrs.Position);
		}
		else if (path.dirty) {
			meshes[path].update(GLMesh.Mesh(vertices, faces));
		}
		return meshes[path];
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

		void set(string uniform)(Color value) {
			alias s = setUniform!(uniform, Color);
			s!((gl.Int loc, Color v) {
				gl.uniform4f(loc, cast(gl.Float) v.r, cast(gl.Float) v.g, cast(gl.Float) v.b, cast(gl.Float) v.a);
			})(value);
		}

		void set(string uniform)(Matrix3 value) {
			alias s = setUniform!(uniform, Matrix3);
			s!((gl.Int loc, Matrix3 v) {
				gl.Float[9] matrixData;
				matrixData[0] = cast(gl.Float) v[0, 0];
				matrixData[1] = cast(gl.Float) v[1, 0];
				matrixData[2] = cast(gl.Float) v[2, 0];
				matrixData[3] = cast(gl.Float) v[0, 1];
				matrixData[4] = cast(gl.Float) v[1, 1];
				matrixData[5] = cast(gl.Float) v[2, 1];
				matrixData[6] = cast(gl.Float) v[0, 2];
				matrixData[7] = cast(gl.Float) v[1, 2];
				matrixData[8] = cast(gl.Float) v[2, 2];
				gl.uniformMatrix3fv(loc, 1, false, matrixData.ptr);
			})(value);
		}

	}

	enum MeshAttrs {
		None = 0,
		Position = 1,
		UV = 8,
	}

	final class GLMesh {
		/** Defines a 3D vertex */
		struct Vertex {
			/** The position of the vertex */
			Vector2 position;

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

		struct Mesh {
			Vertex[] vertices;
			Face[] faces;
		}

		gl.UInt vbo;
		gl.UInt vao;
		gl.UInt ebo;
		size_t numFaces;
		MeshAttrs attrs;

		private size_t stride() {
			size_t result;
			if (attrs & MeshAttrs.Position) {
				result += 2;
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

			if (attrs & MeshAttrs.Position) {
				gl.vertexAttribPointer(array, 2, gl.FLOAT, gl.FALSE, cast(gl.Sizei)(stride * gl.Float.sizeof), cast(void*)(pos * gl.Float.sizeof));
				gl.enableVertexAttribArray(array);
				array += 1;
				pos += 2;
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
				if (attrs & MeshAttrs.Position) {
					vertices[j++] = cast(gl.Float) v.position.x;
					vertices[j++] = cast(gl.Float) v.position.y;
				}
				if (attrs & MeshAttrs.UV) {
					vertices[j++] = cast(gl.Float) v.uv.x;
					vertices[j++] = cast(gl.Float) v.uv.y;
				}
			}
			gl.bufferData(gl.ARRAY_BUFFER, gl.Float.sizeof * mesh.vertices.length * stride, vertices.ptr, gl.STATIC_DRAW);

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
