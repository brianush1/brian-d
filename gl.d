/** OpenGL 3.3 bindings */
module brian.gl;
import std.conv;

// to regenerate docs, run `rdmd -version=brian_gl_docs brian/gl.d`
// generator depends on arsd.dom

// grep 'xplat' to find all platform-specific code
version (Posix) {}
else {
	static assert(0, "brian.gl does not support this platform; open an issue");
}

version (brian_gl_docs) {
	static assert(__traits(compiles, () { import arsd.dom; }), "OpenGL documentation generator depends on arsd.dom");

	void main() {
		import std.algorithm : splitter, joiner, map;
		import std.array : array;
		import std.stdio : File, writeln;

		File self = File("brian/gl.d", "rb");
		string[] lines = self.byLineCopy.map!(to!string).array;
		self.close;

		lines = lines[0 .. OpenGL.startLine];

		string newFuncs = getNewOpenGLFunctions;

		foreach (line; newFuncs.splitter("\n")) {
			lines ~= "\t" ~ line;
		}

		lines ~= "}";

		self = File("brian/gl.d", "wb");
		self.rawWrite(lines.joiner("\n").to!string);
		self.close;
	}

	private string[string] glGetDocsUrls() {
		import arsd.dom : Document;
		import std.string : strip;

		string[string] result;

		Document html = Document.fromUrl("https://www.khronos.org/registry/OpenGL-Refpages/gl4/html/indexflat.php");

		foreach (elem; html.getElementsByTagName("a")) {
			result[elem.innerText.strip] = "https://www.khronos.org/registry/OpenGL-Refpages/gl4/html/" ~ elem.getAttribute("href");
		}

		return result;
	}

	private string[string] glDocsUrls;

	static this() {
		glDocsUrls = glGetDocsUrls;
	}

	private struct GlFunctionDocumentation {
		string returnType;
		string[] paramNames;
		string[] paramTypes;
		string[] paramDescs;
		string description;
	}

	private GlFunctionDocumentation[] glDocs(string[] funcs) {
		import std.parallelism : taskPool;
		import std.array : array;

		return taskPool.map!((string func) {
			import std.stdio : stderr, writeln;

			GlFunctionDocumentation doc;

			string failMsg;

			string glFunc = "gl" ~ cast(char)(func[0] + 'A' - 'a') ~ func[1 .. $];
			if (glFunc !in glDocsUrls) {
				failMsg = "Could not find URL";
				goto fail;
			}
			else {
				auto url = glDocsUrls[glFunc];
				import std.regex : replaceAll, ctRegex;
				import arsd.dom : Document, Selector, Element, NodeType;
				import std.string : strip;
				import std.algorithm : countUntil, canFind, map, joiner, filter;

				Document html = Document.fromUrl(url);

				Element[] selectAll(string selector, Element parent) {
					return Selector(selector).getMatchingElements(parent);
				}

				Element select(string selector, Element parent) {
					return selectAll(selector, parent)[0];
				}

				Element[] selectAllRoot(string selector) {
					return selectAll(selector, html.root);
				}

				Element selectRoot(string selector) {
					return selectAllRoot(selector)[0];
				}

				writeln("Generating documentation for " ~ func ~ "...");

				Element prototypeTable;
				foreach (elem; html.querySelectorAll(`table[class="funcprototype-table"]`)) {
					string elemFunc = select(`[class="fsfunc"]`, elem).innerText.strip;
					if (glFunc == elemFunc) {
						prototypeTable = elem;
						break;
					}
				}
				if (!prototypeTable) {
					failMsg = "Could not find prototype table";
					goto fail;
				}

				Element[] paramElems = selectAll(`[class="pdparam"]`, prototypeTable);

				string convertType(string type) {
					switch (type) {
					case "GLenum": return "Enum";
					case "GLboolean": return "Boolean";
					case "GLbitfield": return "Bitfield";
					case "GLchar": return "Char";
					case "GLbyte": return "Byte";
					case "GLshort": return "Short";
					case "GLint": return "Int";
					case "GLsizei": return "Sizei";
					case "GLubyte": return "UByte";
					case "GLushort": return "UShort";
					case "GLuint": return "UInt";
					case "GLhalf": return "Half";
					case "GLfloat": return "Float";
					case "GLclampf": return "Clampf";
					case "GLdouble": return "Double";
					case "GLclampd": return "Clampd";
					case "GLintptr": return "IntPtr";
					case "GLsizeiptr": return "SizeiPtr";
					case "GLint64": return "Int64";
					case "GLuint64": return "UInt64";
					case "GLhandle": return "Handle";
					case "void": return "void";
					default:
						stderr.writeln("Unexpected type '" ~ type ~ "'; file an issue");
						return type;
					}
				}

				string toplevelTypeText(Element elem) {
					return elem.childNodes.map!((child) {
						if (child.nodeType == NodeType.Text) {
							return child.nodeValue;
						}
						else {
							return "";
						}
					}).joiner.array.to!string.replaceAll(ctRegex!r"(\bconst\b|\W)", "");
				}

				string htmlToDdoc(Element elem, bool trim = false) {
					if (elem.tagName == "mml:math")
						trim = true;
					string[] inner;
					foreach (child; elem.childNodes) {
						if (child.nodeType == NodeType.Text) {
							inner ~= child.nodeValue
								.replaceAll(ctRegex!r"\s+", " ")
								.replaceAll(ctRegex!r"\$\(", "$$(DOLLAR)$$(LPAREN)")
								.replaceAll(ctRegex!r"\`", "$$(BACKTICK)");
							if (trim) {
								inner[$ - 1] = inner[$ - 1].strip;
							}
						}
						else {
							inner ~= htmlToDdoc(child, trim);
						}
					}
					string result = inner.joiner.to!string;
					if (elem.tagName == "b" || elem.tagName == "strong") {
						return "$(B " ~ result ~ ")";
					}
					else if (elem.tagName == "i" || elem.tagName == "em") {
						return "$(I " ~ result ~ ")";
					}
					else if ((elem.classes.canFind("function") || elem.classes.canFind("refentrytitle")) && result.length > 2 && result[0 .. 2] == "gl") {
						return "$(REF " ~ cast(char)(result[2] + 'a' - 'A') ~ result[3 .. $] ~ ")";
					}
					else if (elem.classes.canFind("constant") && result.length > 3 && result[0 .. 3] == "GL_") {
						return "`" ~ result[3 .. $] ~ "`";
					}
					else if (elem.tagName == "code") {
						return "`" ~ result ~ "`";
					}
					else if (elem.tagName == "mml:mo") {
						auto op = result.strip;
						if (op == ">" || op == "<" || op == ">="
							|| op == "<=" || op == "==" || op == "!="
							|| op == "+" || op == "-" || op == "*"
							|| op == "/") {
							return " " ~ op ~ " ";
						}
						else {
							return op;
						}
					}
					else if (elem.tagName == "mml:mfenced") {
						auto open = elem.getAttribute("open");
						auto close = elem.getAttribute("close");
						if (open == "∣") open = "|";
						if (close == "∣") close = "|";
						return open ~ inner.filter!(x => x.strip.length > 0).joiner(", ").to!string ~ close;
					}
					else if (elem.tagName == "mml:math") {
						return result.strip;
					}
					else {
						return result;
					}
				}

				foreach (paramElem; paramElems) {
					if (paramElem.innerText == "void")
						break;
					doc.paramNames ~= paramElem.innerText;
					string paramType = toplevelTypeText(paramElem.parentNode);
					doc.paramTypes ~= convertType(paramType);
				}

				doc.returnType = convertType(toplevelTypeText(select(`[class="funcdef"]`, prototypeTable)));

				string selectSection(string selector) {
					Element section = selectRoot(selector);
					string[] result;
					foreach (child; section.childNodes) {
						if (child.tagName == "p") {
							result ~= htmlToDdoc(child).strip;
						}
						else if (child.tagName == "div" && child.classes.canFind("variablelist")) {
							string lhs;
							foreach (row; select(`dl`, child).childNodes) {
								if (row.tagName == "dt") {
									lhs ~= htmlToDdoc(row).strip;
								}
								else if (row.tagName == "dd") {
									result ~= "- " ~ lhs ~ ": " ~ htmlToDdoc(row).strip;
									lhs = "";
								}
							}
						}
					}
					return result.filter!(x => x.strip.length > 0).joiner("\n\n").to!string;
				}

				doc.description = selectSection(`#description`);

				string[string] paramDescs;
				Element[] varlists = selectAllRoot(`dl[class="variablelist"]`);
				if (varlists.length > 0) {
					string[] params;
					foreach (child; varlists[0].childNodes) {
						if (child.tagName == "dt") {
							params ~= selectAll(`[class="parameter"]`, child).map!(x => x.innerText.strip).array;
						}
						else {
							string[] desc;
							foreach (p; selectAll(`p`, child)) {
								desc ~= htmlToDdoc(p);
							}
							string joinedDesc = desc.joiner("\n\n").to!string.strip;
							if (joinedDesc == "")
								continue;
							foreach (param; params) {
								assert(param !in paramDescs, "parameter " ~ param ~ " redeclared in " ~ glFunc ~ "\n" ~ paramDescs[param] ~ "\n\n\n" ~ joinedDesc);
								paramDescs[param] = joinedDesc;
							}
							params = [];
						}
					}
				}
				foreach (param; doc.paramNames) {
					if (param in paramDescs) {
						doc.paramDescs ~= paramDescs[param];
					}
					else {
						doc.paramDescs ~= "Undocumented in OpenGL reference";
					}
				}
			}

			goto succeed;
			fail:
			stderr.writeln("Could not generate documentation for " ~ func ~ ": " ~ failMsg);
			succeed:
			return doc;
		})(funcs).array;
	}

	string getNewOpenGLFunctions() {
		import std.regex : replaceAll, matchAll, ctRegex, Captures;
		import std.algorithm : countUntil, joiner;
		import std.array : array;

		string result;
		enum Members = {
			string[] members;
			static foreach (member; __traits(allMembers, OpenGL)) {
				static if (is(typeof(&__traits(getMember, OpenGL, member))) && member != "_close") {
					members ~= member;
				}
			}
			return members;
		}();
		auto podRegex = ctRegex!r"(u|)(char|byte|short|int|long|void|float|double)";
		auto docs = glDocs(Members);
		static foreach (i, member; Members) {{
			alias Member = __traits(getMember, OpenGL, member);

			auto doc = docs[i];

			string func = typeof(&Member).stringof;
			func = func.replaceAll(ctRegex!r"\s*extern\s*\(\s*C\s*\)\s*", "");
			func = func.replaceAll(ctRegex!r"\s*nothrow\s*", "");
			func = func.replaceAll(ctRegex!r"\s*@nogc\s*", "");
			func = func.replaceAll(ctRegex!r"function\(\s*void\s*\)", "function()");
			size_t paramsIndex = func.countUntil("function") + "function".length;
			size_t matchIndex;
			if (func[$ - 10 .. $] != "function()") {
				func = func[0 .. paramsIndex].replaceAll(podRegex, doc.returnType) ~ "(" ~ (", " ~ func[paramsIndex + 1 .. $ - 1]).replaceAll!(
					(Captures!string c) {
						size_t i = matchIndex;
						string type = doc.paramTypes[i];
						string name = doc.paramNames[i];
						if (name == "ref") name ~= "_";
						matchIndex++;
						return c.hit.replaceAll(ctRegex!r", (.*) \w+$", ", $1").replaceAll(podRegex, type) ~ " " ~ name;
					})(ctRegex!r", ([^,]*)")[2 .. $] ~ ")";
			}
			func = func.replaceAll(ctRegex!r"function", member);

			string[] docstr;
			docstr ~= doc.description;
			docstr ~= "";
			docstr ~= "Params:";
			foreach (i, desc; doc.paramDescs) {
				docstr ~= doc.paramNames[i] ~ " = " ~ desc;
			}
			result ~= ("/**" ~ docstr ~ "*/\n").joiner("\n").array.to!string ~ func ~ ";\n\n";
		}}
		return result;
	}
}

private T loadSharedLibrary(T, string delegate(string) toLibraryName)(string[] libraries) if (is(T == interface)) {
	enum Members = {
		string[] members;
		static foreach (member; __traits(allMembers, T)) {
			static if (is(typeof(&__traits(getMember, T, member))) && member != "_close") {
				members ~= member;
			}
		}
		return members;
	}();

	class ResultType : T {
		import std.traits : ReturnType, Parameters;

		extern(System) @nogc nothrow:

		void _close() {
			import core.sys.posix.dlfcn : dlclose;

			if (dl !is null) {
				dlclose(dl);
			}
		}

		private void* dl;

		static foreach (member; Members) {
			mixin("
				private ReturnType!(__traits(getMember, T, member)) function(Parameters!(__traits(getMember, T, member))) _impl"~member~";
				ReturnType!(__traits(getMember, T, member)) "~member~"(Parameters!(__traits(getMember, T, member)) args) {
					return _impl"~member~"(args);
				}
			");
		}
	}

	ResultType result = new ResultType;

	// xplat
	version (Posix) {
		import core.sys.posix.dlfcn : dlopen, dlerror, dlsym, RTLD_NOW;
		import std.string : toStringz;

		nextLibrary: foreach (library; libraries) {
			void* dl = dlopen(library.toStringz, RTLD_NOW);
			if (dl) {
				static foreach (member; Members) {{
					dlerror();
					void* sym = dlsym(dl, toLibraryName(member).toStringz);
					if (dlerror()) {
						continue nextLibrary;
					}
					*cast(void**)&__traits(getMember, result, "_impl" ~ member) = sym;
				}}
				return result;
			}
		}
	}
	else {
		static assert(0);
	}

	return null;
}

private size_t glCount;
private OpenGL _gl;

/** Gets the current OpenGL bindings */
OpenGL gl() @property { return _gl; } // @suppress(dscanner.confusing.function_attributes)

/**

Loads OpenGL bindings. This function may be called multiple times. For each time it is called, $(REF unloadGL) should also be called.

Returns: a boolean indicating if loading was a success.

*/
bool loadGL() {
	string[] libraries;

	// xplat
	version (Posix) {
		libraries = ["libGL.so.1", "libGL.so"];
	}
	else {
		static assert(0);
	}

	if (!_gl) {
		_gl = loadSharedLibrary!(OpenGL, delegate(string name) => "gl" ~ cast(char)(name[0] + 'A' - 'a') ~ name[1 .. $])(libraries);
		if (!_gl) {
			return false;
		}
	}
	glCount++;
	return true;
}

/** Unloads the OpenGL bindings */
void unloadGL() {
	glCount--;
	if (glCount == 0 && _gl) {
		_gl._close();
		_gl = null;
	}
}

/** Defines the subset of the OpenGL 3.3 interface which brian.gl supports (includes all of OpenGL 2.1) */
interface OpenGL {
	extern(System) @nogc nothrow:

	void _close();

	/** OpenGL type */
	alias Enum = uint;
	/** OpenGL type */
	alias Boolean = ubyte;
	/** OpenGL type */
	alias Bitfield = uint;
	/** OpenGL type */
	alias Char = char;
	/** OpenGL type */
	alias Byte = byte;
	/** OpenGL type */
	alias Short = short;
	/** OpenGL type */
	alias Int = int;
	/** OpenGL type */
	alias Sizei = int;
	/** OpenGL type */
	alias UByte = ubyte;
	/** OpenGL type */
	alias UShort = ushort;
	/** OpenGL type */
	alias UInt = uint;
	/** OpenGL type */
	alias Half = ushort;
	/** OpenGL type */
	alias Float = float;
	/** OpenGL type */
	alias Clampf = float;
	/** OpenGL type */
	alias Double = double;
	/** OpenGL type */
	alias Clampd = double;
	/** OpenGL type */
	alias IntPtr = ptrdiff_t;
	/** OpenGL type */
	alias SizeiPtr = ptrdiff_t;
	/** OpenGL type */
	alias Int64 = long;
	/** OpenGL type */
	alias UInt64 = ulong;
	/** OpenGL type */
	alias Handle = uint;

	enum : ubyte {
		FALSE = 0,
		TRUE = 1,
	}

	enum : uint {
		DEPTH_BUFFER_BIT = 0x00000100,
		STENCIL_BUFFER_BIT = 0x00000400,
		COLOR_BUFFER_BIT = 0x00004000,
		POINTS = 0x0000,
		LINES = 0x0001,
		LINE_LOOP = 0x0002,
		LINE_STRIP = 0x0003,
		TRIANGLES = 0x0004,
		TRIANGLE_STRIP = 0x0005,
		TRIANGLE_FAN = 0x0006,
		NEVER = 0x0200,
		LESS = 0x0201,
		EQUAL = 0x0202,
		LEQUAL = 0x0203,
		GREATER = 0x0204,
		NOTEQUAL = 0x0205,
		GEQUAL = 0x0206,
		ALWAYS = 0x0207,
		ZERO = 0,
		ONE = 1,
		SRC_COLOR = 0x0300,
		ONE_MINUS_SRC_COLOR = 0x0301,
		SRC_ALPHA = 0x0302,
		ONE_MINUS_SRC_ALPHA = 0x0303,
		DST_ALPHA = 0x0304,
		ONE_MINUS_DST_ALPHA = 0x0305,
		DST_COLOR = 0x0306,
		ONE_MINUS_DST_COLOR = 0x0307,
		SRC_ALPHA_SATURATE = 0x0308,
		NONE = 0,
		FRONT_LEFT = 0x0400,
		FRONT_RIGHT = 0x0401,
		BACK_LEFT = 0x0402,
		BACK_RIGHT = 0x0403,
		FRONT = 0x0404,
		BACK = 0x0405,
		LEFT = 0x0406,
		RIGHT = 0x0407,
		FRONT_AND_BACK = 0x0408,
		NO_ERROR = 0,
		INVALID_ENUM = 0x0500,
		INVALID_VALUE = 0x0501,
		INVALID_OPERATION = 0x0502,
		OUT_OF_MEMORY = 0x0505,
		CW = 0x0900,
		CCW = 0x0901,
		POINT_SIZE = 0x0B11,
		POINT_SIZE_RANGE = 0x0B12,
		POINT_SIZE_GRANULARITY = 0x0B13,
		LINE_SMOOTH = 0x0B20,
		LINE_WIDTH = 0x0B21,
		LINE_WIDTH_RANGE = 0x0B22,
		LINE_WIDTH_GRANULARITY = 0x0B23,
		POLYGON_MODE = 0x0B40,
		POLYGON_SMOOTH = 0x0B41,
		CULL_FACE = 0x0B44,
		CULL_FACE_MODE = 0x0B45,
		FRONT_FACE = 0x0B46,
		DEPTH_RANGE = 0x0B70,
		DEPTH_TEST = 0x0B71,
		DEPTH_WRITEMASK = 0x0B72,
		DEPTH_CLEAR_VALUE = 0x0B73,
		DEPTH_FUNC = 0x0B74,
		STENCIL_TEST = 0x0B90,
		STENCIL_CLEAR_VALUE = 0x0B91,
		STENCIL_FUNC = 0x0B92,
		STENCIL_VALUE_MASK = 0x0B93,
		STENCIL_FAIL = 0x0B94,
		STENCIL_PASS_DEPTH_FAIL = 0x0B95,
		STENCIL_PASS_DEPTH_PASS = 0x0B96,
		STENCIL_REF = 0x0B97,
		STENCIL_WRITEMASK = 0x0B98,
		VIEWPORT = 0x0BA2,
		DITHER = 0x0BD0,
		BLEND_DST = 0x0BE0,
		BLEND_SRC = 0x0BE1,
		BLEND = 0x0BE2,
		LOGIC_OP_MODE = 0x0BF0,
		COLOR_LOGIC_OP = 0x0BF2,
		DRAW_BUFFER = 0x0C01,
		READ_BUFFER = 0x0C02,
		SCISSOR_BOX = 0x0C10,
		SCISSOR_TEST = 0x0C11,
		COLOR_CLEAR_VALUE = 0x0C22,
		COLOR_WRITEMASK = 0x0C23,
		DOUBLEBUFFER = 0x0C32,
		STEREO = 0x0C33,
		LINE_SMOOTH_HINT = 0x0C52,
		POLYGON_SMOOTH_HINT = 0x0C53,
		UNPACK_SWAP_BYTES = 0x0CF0,
		UNPACK_LSB_FIRST = 0x0CF1,
		UNPACK_ROW_LENGTH = 0x0CF2,
		UNPACK_SKIP_ROWS = 0x0CF3,
		UNPACK_SKIP_PIXELS = 0x0CF4,
		UNPACK_ALIGNMENT = 0x0CF5,
		PACK_SWAP_BYTES = 0x0D00,
		PACK_LSB_FIRST = 0x0D01,
		PACK_ROW_LENGTH = 0x0D02,
		PACK_SKIP_ROWS = 0x0D03,
		PACK_SKIP_PIXELS = 0x0D04,
		PACK_ALIGNMENT = 0x0D05,
		MAX_TEXTURE_SIZE = 0x0D33,
		MAX_VIEWPORT_DIMS = 0x0D3A,
		SUBPIXEL_BITS = 0x0D50,
		TEXTURE_1D = 0x0DE0,
		TEXTURE_2D = 0x0DE1,
		POLYGON_OFFSET_UNITS = 0x2A00,
		POLYGON_OFFSET_POINT = 0x2A01,
		POLYGON_OFFSET_LINE = 0x2A02,
		POLYGON_OFFSET_FILL = 0x8037,
		POLYGON_OFFSET_FACTOR = 0x8038,
		TEXTURE_BINDING_1D = 0x8068,
		TEXTURE_BINDING_2D = 0x8069,
		TEXTURE_WIDTH = 0x1000,
		TEXTURE_HEIGHT = 0x1001,
		TEXTURE_INTERNAL_FORMAT = 0x1003,
		TEXTURE_BORDER_COLOR = 0x1004,
		TEXTURE_RED_SIZE = 0x805C,
		TEXTURE_GREEN_SIZE = 0x805D,
		TEXTURE_BLUE_SIZE = 0x805E,
		TEXTURE_ALPHA_SIZE = 0x805F,
		DONT_CARE = 0x1100,
		FASTEST = 0x1101,
		NICEST = 0x1102,
		BYTE = 0x1400,
		UNSIGNED_BYTE = 0x1401,
		SHORT = 0x1402,
		UNSIGNED_SHORT = 0x1403,
		INT = 0x1404,
		UNSIGNED_INT = 0x1405,
		FLOAT = 0x1406,
		DOUBLE = 0x140A,
		CLEAR = 0x1500,
		AND = 0x1501,
		AND_REVERSE = 0x1502,
		COPY = 0x1503,
		AND_INVERTED = 0x1504,
		NOOP = 0x1505,
		XOR = 0x1506,
		OR = 0x1507,
		NOR = 0x1508,
		EQUIV = 0x1509,
		INVERT = 0x150A,
		OR_REVERSE = 0x150B,
		COPY_INVERTED = 0x150C,
		OR_INVERTED = 0x150D,
		NAND = 0x150E,
		SET = 0x150F,
		TEXTURE = 0x1702,
		COLOR = 0x1800,
		DEPTH = 0x1801,
		STENCIL = 0x1802,
		STENCIL_INDEX = 0x1901,
		DEPTH_COMPONENT = 0x1902,
		RED = 0x1903,
		GREEN = 0x1904,
		BLUE = 0x1905,
		ALPHA = 0x1906,
		RGB = 0x1907,
		RGBA = 0x1908,
		POINT = 0x1B00,
		LINE = 0x1B01,
		FILL = 0x1B02,
		KEEP = 0x1E00,
		REPLACE = 0x1E01,
		INCR = 0x1E02,
		DECR = 0x1E03,
		VENDOR = 0x1F00,
		RENDERER = 0x1F01,
		VERSION = 0x1F02,
		EXTENSIONS = 0x1F03,
		NEAREST = 0x2600,
		LINEAR = 0x2601,
		NEAREST_MIPMAP_NEAREST = 0x2700,
		LINEAR_MIPMAP_NEAREST = 0x2701,
		NEAREST_MIPMAP_LINEAR = 0x2702,
		LINEAR_MIPMAP_LINEAR = 0x2703,
		TEXTURE_MAG_FILTER = 0x2800,
		TEXTURE_MIN_FILTER = 0x2801,
		TEXTURE_WRAP_S = 0x2802,
		TEXTURE_WRAP_T = 0x2803,
		PROXY_TEXTURE_1D = 0x8063,
		PROXY_TEXTURE_2D = 0x8064,
		REPEAT = 0x2901,
		R3_G3_B2 = 0x2A10,
		RGB4 = 0x804F,
		RGB5 = 0x8050,
		RGB8 = 0x8051,
		RGB10 = 0x8052,
		RGB12 = 0x8053,
		RGB16 = 0x8054,
		RGBA2 = 0x8055,
		RGBA4 = 0x8056,
		RGB5_A1 = 0x8057,
		RGBA8 = 0x8058,
		RGB10_A2 = 0x8059,
		RGBA12 = 0x805A,
		RGBA16 = 0x805B,
		VERTEX_ARRAY = 0x8074,
		UNSIGNED_BYTE_3_3_2 = 0x8032,
		UNSIGNED_SHORT_4_4_4_4 = 0x8033,
		UNSIGNED_SHORT_5_5_5_1 = 0x8034,
		UNSIGNED_INT_8_8_8_8 = 0x8035,
		UNSIGNED_INT_10_10_10_2 = 0x8036,
		TEXTURE_BINDING_3D = 0x806A,
		PACK_SKIP_IMAGES = 0x806B,
		PACK_IMAGE_HEIGHT = 0x806C,
		UNPACK_SKIP_IMAGES = 0x806D,
		UNPACK_IMAGE_HEIGHT = 0x806E,
		TEXTURE_3D = 0x806F,
		PROXY_TEXTURE_3D = 0x8070,
		TEXTURE_DEPTH = 0x8071,
		TEXTURE_WRAP_R = 0x8072,
		MAX_3D_TEXTURE_SIZE = 0x8073,
		UNSIGNED_BYTE_2_3_3_REV = 0x8362,
		UNSIGNED_SHORT_5_6_5 = 0x8363,
		UNSIGNED_SHORT_5_6_5_REV = 0x8364,
		UNSIGNED_SHORT_4_4_4_4_REV = 0x8365,
		UNSIGNED_SHORT_1_5_5_5_REV = 0x8366,
		UNSIGNED_INT_8_8_8_8_REV = 0x8367,
		UNSIGNED_INT_2_10_10_10_REV = 0x8368,
		BGR = 0x80E0,
		BGRA = 0x80E1,
		MAX_ELEMENTS_VERTICES = 0x80E8,
		MAX_ELEMENTS_INDICES = 0x80E9,
		CLAMP_TO_EDGE = 0x812F,
		TEXTURE_MIN_LOD = 0x813A,
		TEXTURE_MAX_LOD = 0x813B,
		TEXTURE_BASE_LEVEL = 0x813C,
		TEXTURE_MAX_LEVEL = 0x813D,
		SMOOTH_POINT_SIZE_RANGE = 0x0B12,
		SMOOTH_POINT_SIZE_GRANULARITY = 0x0B13,
		SMOOTH_LINE_WIDTH_RANGE = 0x0B22,
		SMOOTH_LINE_WIDTH_GRANULARITY = 0x0B23,
		ALIASED_LINE_WIDTH_RANGE = 0x846E,
		TEXTURE0 = 0x84C0,
		TEXTURE1 = 0x84C1,
		TEXTURE2 = 0x84C2,
		TEXTURE3 = 0x84C3,
		TEXTURE4 = 0x84C4,
		TEXTURE5 = 0x84C5,
		TEXTURE6 = 0x84C6,
		TEXTURE7 = 0x84C7,
		TEXTURE8 = 0x84C8,
		TEXTURE9 = 0x84C9,
		TEXTURE10 = 0x84CA,
		TEXTURE11 = 0x84CB,
		TEXTURE12 = 0x84CC,
		TEXTURE13 = 0x84CD,
		TEXTURE14 = 0x84CE,
		TEXTURE15 = 0x84CF,
		TEXTURE16 = 0x84D0,
		TEXTURE17 = 0x84D1,
		TEXTURE18 = 0x84D2,
		TEXTURE19 = 0x84D3,
		TEXTURE20 = 0x84D4,
		TEXTURE21 = 0x84D5,
		TEXTURE22 = 0x84D6,
		TEXTURE23 = 0x84D7,
		TEXTURE24 = 0x84D8,
		TEXTURE25 = 0x84D9,
		TEXTURE26 = 0x84DA,
		TEXTURE27 = 0x84DB,
		TEXTURE28 = 0x84DC,
		TEXTURE29 = 0x84DD,
		TEXTURE30 = 0x84DE,
		TEXTURE31 = 0x84DF,
		ACTIVE_TEXTURE = 0x84E0,
		MULTISAMPLE = 0x809D,
		SAMPLE_ALPHA_TO_COVERAGE = 0x809E,
		SAMPLE_ALPHA_TO_ONE = 0x809F,
		SAMPLE_COVERAGE = 0x80A0,
		SAMPLE_BUFFERS = 0x80A8,
		SAMPLES = 0x80A9,
		SAMPLE_COVERAGE_VALUE = 0x80AA,
		SAMPLE_COVERAGE_INVERT = 0x80AB,
		TEXTURE_CUBE_MAP = 0x8513,
		TEXTURE_BINDING_CUBE_MAP = 0x8514,
		TEXTURE_CUBE_MAP_POSITIVE_X = 0x8515,
		TEXTURE_CUBE_MAP_NEGATIVE_X = 0x8516,
		TEXTURE_CUBE_MAP_POSITIVE_Y = 0x8517,
		TEXTURE_CUBE_MAP_NEGATIVE_Y = 0x8518,
		TEXTURE_CUBE_MAP_POSITIVE_Z = 0x8519,
		TEXTURE_CUBE_MAP_NEGATIVE_Z = 0x851A,
		PROXY_TEXTURE_CUBE_MAP = 0x851B,
		MAX_CUBE_MAP_TEXTURE_SIZE = 0x851C,
		COMPRESSED_RGB = 0x84ED,
		COMPRESSED_RGBA = 0x84EE,
		TEXTURE_COMPRESSION_HINT = 0x84EF,
		TEXTURE_COMPRESSED_IMAGE_SIZE = 0x86A0,
		TEXTURE_COMPRESSED = 0x86A1,
		NUM_COMPRESSED_TEXTURE_FORMATS = 0x86A2,
		COMPRESSED_TEXTURE_FORMATS = 0x86A3,
		CLAMP_TO_BORDER = 0x812D,
		BLEND_DST_RGB = 0x80C8,
		BLEND_SRC_RGB = 0x80C9,
		BLEND_DST_ALPHA = 0x80CA,
		BLEND_SRC_ALPHA = 0x80CB,
		POINT_FADE_THRESHOLD_SIZE = 0x8128,
		DEPTH_COMPONENT16 = 0x81A5,
		DEPTH_COMPONENT24 = 0x81A6,
		DEPTH_COMPONENT32 = 0x81A7,
		MIRRORED_REPEAT = 0x8370,
		MAX_TEXTURE_LOD_BIAS = 0x84FD,
		TEXTURE_LOD_BIAS = 0x8501,
		INCR_WRAP = 0x8507,
		DECR_WRAP = 0x8508,
		TEXTURE_DEPTH_SIZE = 0x884A,
		TEXTURE_COMPARE_MODE = 0x884C,
		TEXTURE_COMPARE_FUNC = 0x884D,
		CONSTANT_COLOR = 0x8001,
		ONE_MINUS_CONSTANT_COLOR = 0x8002,
		CONSTANT_ALPHA = 0x8003,
		ONE_MINUS_CONSTANT_ALPHA = 0x8004,
		FUNC_ADD = 0x8006,
		MIN = 0x8007,
		MAX = 0x8008,
		FUNC_SUBTRACT = 0x800A,
		FUNC_REVERSE_SUBTRACT = 0x800B,
		BUFFER_SIZE = 0x8764,
		BUFFER_USAGE = 0x8765,
		QUERY_COUNTER_BITS = 0x8864,
		CURRENT_QUERY = 0x8865,
		QUERY_RESULT = 0x8866,
		QUERY_RESULT_AVAILABLE = 0x8867,
		ARRAY_BUFFER = 0x8892,
		ELEMENT_ARRAY_BUFFER = 0x8893,
		ARRAY_BUFFER_BINDING = 0x8894,
		ELEMENT_ARRAY_BUFFER_BINDING = 0x8895,
		VERTEX_ATTRIB_ARRAY_BUFFER_BINDING = 0x889F,
		READ_ONLY = 0x88B8,
		WRITE_ONLY = 0x88B9,
		READ_WRITE = 0x88BA,
		BUFFER_ACCESS = 0x88BB,
		BUFFER_MAPPED = 0x88BC,
		BUFFER_MAP_POINTER = 0x88BD,
		STREAM_DRAW = 0x88E0,
		STREAM_READ = 0x88E1,
		STREAM_COPY = 0x88E2,
		STATIC_DRAW = 0x88E4,
		STATIC_READ = 0x88E5,
		STATIC_COPY = 0x88E6,
		DYNAMIC_DRAW = 0x88E8,
		DYNAMIC_READ = 0x88E9,
		DYNAMIC_COPY = 0x88EA,
		SAMPLES_PASSED = 0x8914,
		SRC1_ALPHA = 0x8589,
		BLEND_EQUATION_RGB = 0x8009,
		VERTEX_ATTRIB_ARRAY_ENABLED = 0x8622,
		VERTEX_ATTRIB_ARRAY_SIZE = 0x8623,
		VERTEX_ATTRIB_ARRAY_STRIDE = 0x8624,
		VERTEX_ATTRIB_ARRAY_TYPE = 0x8625,
		CURRENT_VERTEX_ATTRIB = 0x8626,
		VERTEX_PROGRAM_POINT_SIZE = 0x8642,
		VERTEX_ATTRIB_ARRAY_POINTER = 0x8645,
		STENCIL_BACK_FUNC = 0x8800,
		STENCIL_BACK_FAIL = 0x8801,
		STENCIL_BACK_PASS_DEPTH_FAIL = 0x8802,
		STENCIL_BACK_PASS_DEPTH_PASS = 0x8803,
		MAX_DRAW_BUFFERS = 0x8824,
		DRAW_BUFFER0 = 0x8825,
		DRAW_BUFFER1 = 0x8826,
		DRAW_BUFFER2 = 0x8827,
		DRAW_BUFFER3 = 0x8828,
		DRAW_BUFFER4 = 0x8829,
		DRAW_BUFFER5 = 0x882A,
		DRAW_BUFFER6 = 0x882B,
		DRAW_BUFFER7 = 0x882C,
		DRAW_BUFFER8 = 0x882D,
		DRAW_BUFFER9 = 0x882E,
		DRAW_BUFFER10 = 0x882F,
		DRAW_BUFFER11 = 0x8830,
		DRAW_BUFFER12 = 0x8831,
		DRAW_BUFFER13 = 0x8832,
		DRAW_BUFFER14 = 0x8833,
		DRAW_BUFFER15 = 0x8834,
		BLEND_EQUATION_ALPHA = 0x883D,
		MAX_VERTEX_ATTRIBS = 0x8869,
		VERTEX_ATTRIB_ARRAY_NORMALIZED = 0x886A,
		MAX_TEXTURE_IMAGE_UNITS = 0x8872,
		FRAGMENT_SHADER = 0x8B30,
		VERTEX_SHADER = 0x8B31,
		MAX_FRAGMENT_UNIFORM_COMPONENTS = 0x8B49,
		MAX_VERTEX_UNIFORM_COMPONENTS = 0x8B4A,
		MAX_VARYING_FLOATS = 0x8B4B,
		MAX_VERTEX_TEXTURE_IMAGE_UNITS = 0x8B4C,
		MAX_COMBINED_TEXTURE_IMAGE_UNITS = 0x8B4D,
		SHADER_TYPE = 0x8B4F,
		FLOAT_VEC2 = 0x8B50,
		FLOAT_VEC3 = 0x8B51,
		FLOAT_VEC4 = 0x8B52,
		INT_VEC2 = 0x8B53,
		INT_VEC3 = 0x8B54,
		INT_VEC4 = 0x8B55,
		BOOL = 0x8B56,
		BOOL_VEC2 = 0x8B57,
		BOOL_VEC3 = 0x8B58,
		BOOL_VEC4 = 0x8B59,
		FLOAT_MAT2 = 0x8B5A,
		FLOAT_MAT3 = 0x8B5B,
		FLOAT_MAT4 = 0x8B5C,
		SAMPLER_1D = 0x8B5D,
		SAMPLER_2D = 0x8B5E,
		SAMPLER_3D = 0x8B5F,
		SAMPLER_CUBE = 0x8B60,
		SAMPLER_1D_SHADOW = 0x8B61,
		SAMPLER_2D_SHADOW = 0x8B62,
		DELETE_STATUS = 0x8B80,
		COMPILE_STATUS = 0x8B81,
		LINK_STATUS = 0x8B82,
		VALIDATE_STATUS = 0x8B83,
		INFO_LOG_LENGTH = 0x8B84,
		ATTACHED_SHADERS = 0x8B85,
		ACTIVE_UNIFORMS = 0x8B86,
		ACTIVE_UNIFORM_MAX_LENGTH = 0x8B87,
		SHADER_SOURCE_LENGTH = 0x8B88,
		ACTIVE_ATTRIBUTES = 0x8B89,
		ACTIVE_ATTRIBUTE_MAX_LENGTH = 0x8B8A,
		FRAGMENT_SHADER_DERIVATIVE_HINT = 0x8B8B,
		SHADING_LANGUAGE_VERSION = 0x8B8C,
		CURRENT_PROGRAM = 0x8B8D,
		POINT_SPRITE_COORD_ORIGIN = 0x8CA0,
		LOWER_LEFT = 0x8CA1,
		UPPER_LEFT = 0x8CA2,
		STENCIL_BACK_REF = 0x8CA3,
		STENCIL_BACK_VALUE_MASK = 0x8CA4,
		STENCIL_BACK_WRITEMASK = 0x8CA5,
		PIXEL_PACK_BUFFER = 0x88EB,
		PIXEL_UNPACK_BUFFER = 0x88EC,
		PIXEL_PACK_BUFFER_BINDING = 0x88ED,
		PIXEL_UNPACK_BUFFER_BINDING = 0x88EF,
		FLOAT_MAT2x3 = 0x8B65,
		FLOAT_MAT2x4 = 0x8B66,
		FLOAT_MAT3x2 = 0x8B67,
		FLOAT_MAT3x4 = 0x8B68,
		FLOAT_MAT4x2 = 0x8B69,
		FLOAT_MAT4x3 = 0x8B6A,
		SRGB = 0x8C40,
		SRGB8 = 0x8C41,
		SRGB_ALPHA = 0x8C42,
		SRGB8_ALPHA8 = 0x8C43,
		COMPRESSED_SRGB = 0x8C48,
		COMPRESSED_SRGB_ALPHA = 0x8C49,
		VERTEX_ARRAY_BINDING = 0x85B5,
	}

	version (brian_gl_docs) {
		private enum startLine = __LINE__ + 2;
	}

	/**
	$(REF cullFace) specifies whether front- or back-facing facets are culled (as specified by $(I mode)) when facet culling is enabled. Facet culling is initially disabled. To enable and disable facet culling, call the $(REF enable) and $(REF disable) commands with the argument `CULL_FACE`. Facets include triangles, quadrilaterals, polygons, and rectangles.
	
	$(REF frontFace) specifies which of the clockwise and counterclockwise facets are front-facing and back-facing. See $(REF frontFace).
	
	Params:
	mode = Specifies whether front- or back-facing facets are candidates for culling. Symbolic constants `FRONT`, `BACK`, and `FRONT_AND_BACK` are accepted. The initial value is `BACK`.
	*/
	void cullFace(Enum mode);
	
	/**
	In a scene composed entirely of opaque closed surfaces, back-facing polygons are never visible. Eliminating these invisible polygons has the obvious benefit of speeding up the rendering of the image. To enable and disable elimination of back-facing polygons, call $(REF enable) and $(REF disable) with argument `CULL_FACE`.
	
	The projection of a polygon to window coordinates is said to have clockwise winding if an imaginary object following the path from its first vertex, its second vertex, and so on, to its last vertex, and finally back to its first vertex, moves in a clockwise direction about the interior of the polygon. The polygon's winding is said to be counterclockwise if the imaginary object following the same path moves in a counterclockwise direction about the interior of the polygon. $(REF frontFace) specifies whether polygons with clockwise winding in window coordinates, or counterclockwise winding in window coordinates, are taken to be front-facing. Passing `CCW` to $(I `mode`) selects counterclockwise polygons as front-facing; `CW` selects clockwise polygons as front-facing. By default, counterclockwise polygons are taken to be front-facing.
	
	Params:
	mode = Specifies the orientation of front-facing polygons. `CW` and `CCW` are accepted. The initial value is `CCW`.
	*/
	void frontFace(Enum mode);
	
	/**
	Certain aspects of GL behavior, when there is room for interpretation, can be controlled with hints. A hint is specified with two arguments. $(I `target`) is a symbolic constant indicating the behavior to be controlled, and $(I `mode`) is another symbolic constant indicating the desired behavior. The initial value for each $(I `target`) is `DONT_CARE`. $(I `mode`) can be one of the following:
	
	- `FASTEST`: The most efficient option should be chosen.
	
	- `NICEST`: The most correct, or highest quality, option should be chosen.
	
	- `DONT_CARE`: No preference.
	
	Though the implementation aspects that can be hinted are well defined, the interpretation of the hints depends on the implementation. The hint aspects that can be specified with $(I `target`), along with suggested semantics, are as follows:
	
	- `FRAGMENT_SHADER_DERIVATIVE_HINT`: Indicates the accuracy of the derivative calculation for the GL shading language fragment processing built-in functions: `dFdx`, `dFdy`, and `fwidth`.
	
	- `LINE_SMOOTH_HINT`: Indicates the sampling quality of antialiased lines. If a larger filter function is applied, hinting `NICEST` can result in more pixel fragments being generated during rasterization.
	
	- `POLYGON_SMOOTH_HINT`: Indicates the sampling quality of antialiased polygons. Hinting `NICEST` can result in more pixel fragments being generated during rasterization, if a larger filter function is applied.
	
	- `TEXTURE_COMPRESSION_HINT`: Indicates the quality and performance of the compressing texture images. Hinting `FASTEST` indicates that texture images should be compressed as quickly as possible, while `NICEST` indicates that texture images should be compressed with as little image quality loss as possible. `NICEST` should be selected if the texture is to be retrieved by $(REF getCompressedTexImage) for reuse.
	
	Params:
	target = Specifies a symbolic constant indicating the behavior to be controlled. `LINE_SMOOTH_HINT`, `POLYGON_SMOOTH_HINT`, `TEXTURE_COMPRESSION_HINT`, and `FRAGMENT_SHADER_DERIVATIVE_HINT` are accepted.
	mode = Specifies a symbolic constant indicating the desired behavior. `FASTEST`, `NICEST`, and `DONT_CARE` are accepted.
	*/
	void hint(Enum target, Enum mode);
	
	/**
	$(REF lineWidth) specifies the rasterized width of both aliased and antialiased lines. Using a line width other than 1 has different effects, depending on whether line antialiasing is enabled. To enable and disable line antialiasing, call $(REF enable) and $(REF disable) with argument `LINE_SMOOTH`. Line antialiasing is initially disabled.
	
	If line antialiasing is disabled, the actual width is determined by rounding the supplied width to the nearest integer. (If the rounding results in the value 0, it is as if the line width were 1.) If |Δx| >= |Δy|, $(I i) pixels are filled in each column that is rasterized, where $(I i) is the rounded value of $(I `width`). Otherwise, $(I i) pixels are filled in each row that is rasterized.
	
	If antialiasing is enabled, line rasterization produces a fragment for each pixel square that intersects the region lying within the rectangle having width equal to the current line width, length equal to the actual length of the line, and centered on the mathematical line segment. The coverage value for each fragment is the window coordinate area of the intersection of the rectangular region with the corresponding pixel square. This value is saved and used in the final rasterization step.
	
	Not all widths can be supported when line antialiasing is enabled. If an unsupported width is requested, the nearest supported width is used. Only width 1 is guaranteed to be supported; others depend on the implementation. Likewise, there is a range for aliased line widths as well. To query the range of supported widths and the size difference between supported widths within the range, call $(REF get) with arguments `ALIASED_LINE_WIDTH_RANGE`, `SMOOTH_LINE_WIDTH_RANGE`, and `SMOOTH_LINE_WIDTH_GRANULARITY`.
	
	Params:
	width = Specifies the width of rasterized lines. The initial value is 1.
	*/
	void lineWidth(Float width);
	
	/**
	$(REF pointSize) specifies the rasterized diameter of points. If point size mode is disabled (see $(REF enable) with parameter `PROGRAM_POINT_SIZE`), this value will be used to rasterize points. Otherwise, the value written to the shading language built-in variable `gl_PointSize` will be used.
	
	Params:
	size = Specifies the diameter of rasterized points. The initial value is 1.
	*/
	void pointSize(Float size);
	
	/**
	$(REF polygonMode) controls the interpretation of polygons for rasterization. $(I `face`) describes which polygons $(I `mode`) applies to: both front and back-facing polygons (`FRONT_AND_BACK`). The polygon mode affects only the final rasterization of polygons. In particular, a polygon's vertices are lit and the polygon is clipped and possibly culled before these modes are applied.
	
	Three modes are defined and can be specified in $(I `mode`):
	
	- `POINT`: Polygon vertices that are marked as the start of a boundary edge are drawn as points. Point attributes such as `POINT_SIZE` and `POINT_SMOOTH` control the rasterization of the points. Polygon rasterization attributes other than `POLYGON_MODE` have no effect.
	
	- `LINE`: Boundary edges of the polygon are drawn as line segments. Line attributes such as `LINE_WIDTH` and `LINE_SMOOTH` control the rasterization of the lines. Polygon rasterization attributes other than `POLYGON_MODE` have no effect.
	
	- `FILL`: The interior of the polygon is filled. Polygon attributes such as `POLYGON_SMOOTH` control the rasterization of the polygon.
	
	Params:
	face = Specifies the polygons that $(I `mode`) applies to. Must be `FRONT_AND_BACK` for front- and back-facing polygons.
	mode = Specifies how polygons will be rasterized. Accepted values are `POINT`, `LINE`, and `FILL`. The initial value is `FILL` for both front- and back-facing polygons.
	*/
	void polygonMode(Enum face, Enum mode);
	
	/**
	$(REF scissor) defines a rectangle, called the scissor box, in window coordinates. The first two arguments, $(I `x`) and $(I `y`), specify the lower left corner of the box. $(I `width`) and $(I `height`) specify the width and height of the box.
	
	To enable and disable the scissor test, call $(REF enable) and $(REF disable) with argument `SCISSOR_TEST`. The test is initially disabled. While the test is enabled, only pixels that lie within the scissor box can be modified by drawing commands. Window coordinates have integer values at the shared corners of frame buffer pixels. `glScissor(0,0,1,1)` allows modification of only the lower left pixel in the window, and `glScissor(0,0,0,0)` doesn't allow modification of any pixels in the window.
	
	When the scissor test is disabled, it is as though the scissor box includes the entire window.
	
	Params:
	x = Specify the lower left corner of the scissor box. Initially (0, 0).
	y = Specify the lower left corner of the scissor box. Initially (0, 0).
	width = Specify the width and height of the scissor box. When a GL context is first attached to a window, $(I `width`) and $(I `height`) are set to the dimensions of that window.
	height = Specify the width and height of the scissor box. When a GL context is first attached to a window, $(I `width`) and $(I `height`) are set to the dimensions of that window.
	*/
	void scissor(Int x, Int y, Sizei width, Sizei height);
	
	/**
	$(REF texParameter) and $(REF textureParameter) assign the value or values in $(I `params`) to the texture parameter specified as $(I `pname`). For $(REF texParameter), $(I `target`) defines the target texture, either `TEXTURE_1D`, `TEXTURE_1D_ARRAY`, `TEXTURE_2D`, `TEXTURE_2D_ARRAY`, `TEXTURE_2D_MULTISAMPLE`, `TEXTURE_2D_MULTISAMPLE_ARRAY`, `TEXTURE_3D`, `TEXTURE_CUBE_MAP`, `TEXTURE_CUBE_MAP_ARRAY`, or `TEXTURE_RECTANGLE`. The following symbols are accepted in $(I `pname`):
	
	- `DEPTH_STENCIL_TEXTURE_MODE`: Specifies the mode used to read from depth-stencil format textures. $(I `params`) must be one of `DEPTH_COMPONENT` or `STENCIL_INDEX`. If the depth stencil mode is `DEPTH_COMPONENT`, then reads from depth-stencil format textures will return the depth component of the texel in Rt and the stencil component will be discarded. If the depth stencil mode is `STENCIL_INDEX` then the stencil component is returned in Rt and the depth component is discarded. The initial value is `DEPTH_COMPONENT`.
	
	- `TEXTURE_BASE_LEVEL`: Specifies the index of the lowest defined mipmap level. This is an integer value. The initial value is 0.
	
	- `TEXTURE_BORDER_COLOR`: The data in $(I `params`) specifies four values that define the border values that should be used for border texels. If a texel is sampled from the border of the texture, the values of `TEXTURE_BORDER_COLOR` are interpreted as an RGBA color to match the texture's internal format and substituted for the non-existent texel data. If the texture contains depth components, the first component of `TEXTURE_BORDER_COLOR` is interpreted as a depth value. The initial value is     0.0 , 0.0 , 0.0 , 0.0    .   If the values for `TEXTURE_BORDER_COLOR` are specified with $(REF texParameterIiv) or $(REF texParameterIuiv), the values are stored unmodified with an internal data type of integer. If specified with $(REF texParameteriv), they are converted to floating point with the following equation:   f =   2 c + 1    2 b  - 1    . If specified with $(REF texParameterfv), they are stored unmodified as floating-point values.
	
	- `TEXTURE_COMPARE_FUNC`: Specifies the comparison operator used when `TEXTURE_COMPARE_MODE` is set to `COMPARE_REF_TO_TEXTURE`. Permissible values are:           $(B  Texture Comparison Function )   $(B  Computed result )       `LEQUAL`     result =     1.0   0.0   ⁢     r <=  D t       r >  D t              `GEQUAL`     result =     1.0   0.0   ⁢     r >=  D t       r <  D t              `LESS`     result =     1.0   0.0   ⁢     r <  D t       r >=  D t              `GREATER`     result =     1.0   0.0   ⁢     r >  D t       r <=  D t              `EQUAL`     result =     1.0   0.0   ⁢     r =  D t       r ≠  D t              `NOTEQUAL`     result =     1.0   0.0   ⁢     r ≠  D t       r =  D t              `ALWAYS`     result = 1.0       `NEVER`     result = 0.0         where r is the current interpolated texture coordinate, and  D t   is the depth texture value sampled from the currently bound depth texture. result is assigned to the red channel.
	
	- `TEXTURE_COMPARE_MODE`: Specifies the texture comparison mode for currently bound depth textures. That is, a texture whose internal format is `DEPTH_COMPONENT_*`; see $(REF texImage2D)) Permissible values are:      `COMPARE_REF_TO_TEXTURE`     Specifies that the interpolated and clamped r texture coordinate should be compared to the value in the currently bound depth texture. See the discussion of `TEXTURE_COMPARE_FUNC` for details of how the comparison is evaluated. The result of the comparison is assigned to the red channel.     `NONE`     Specifies that the red channel should be assigned the appropriate value from the currently bound depth texture.
	
	- `TEXTURE_LOD_BIAS`: $(I `params`) specifies a fixed bias value that is to be added to the level-of-detail parameter for the texture before texture sampling. The specified value is added to the shader-supplied bias value (if any) and subsequently clamped into the implementation-defined range     -  bias max        bias max      , where   bias max    is the value of the implementation defined constant `MAX_TEXTURE_LOD_BIAS`. The initial value is 0.0.
	
	- `TEXTURE_MIN_FILTER`: The texture minifying function is used whenever the level-of-detail function used when sampling from the texture determines that the texture should be minified. There are six defined minifying functions. Two of them use either the nearest texture elements or a weighted average of multiple texture elements to compute the texture value. The other four use mipmaps.   A mipmap is an ordered set of arrays representing the same image at progressively lower resolutions. If the texture has dimensions   2 n  × 2 m   , there are    max ⁡  n m   + 1   mipmaps. The first mipmap is the original texture, with dimensions   2 n  × 2 m   . Each subsequent mipmap has dimensions   2   k - 1    × 2   l - 1     , where   2 k  × 2 l    are the dimensions of the previous mipmap, until either   k = 0   or   l = 0  . At that point, subsequent mipmaps have dimension   1 × 2   l - 1      or   2   k - 1    × 1   until the final mipmap, which has dimension   1 × 1  . To define the mipmaps, call $(REF texImage1D), $(REF texImage2D), $(REF texImage3D), $(REF copyTexImage1D), or $(REF copyTexImage2D) with the $(I level) argument indicating the order of the mipmaps. Level 0 is the original texture; level   max ⁡  n m    is the final   1 × 1   mipmap.   $(I `params`) supplies a function for minifying the texture as one of the following:      `NEAREST`     Returns the value of the texture element that is nearest (in Manhattan distance) to the specified texture coordinates.     `LINEAR`     Returns the weighted average of the four texture elements that are closest to the specified texture coordinates. These can include items wrapped or repeated from other parts of a texture, depending on the values of `TEXTURE_WRAP_S` and `TEXTURE_WRAP_T`, and on the exact mapping.     `NEAREST_MIPMAP_NEAREST`     Chooses the mipmap that most closely matches the size of the pixel being textured and uses the `NEAREST` criterion (the texture element closest to the specified texture coordinates) to produce a texture value.     `LINEAR_MIPMAP_NEAREST`     Chooses the mipmap that most closely matches the size of the pixel being textured and uses the `LINEAR` criterion (a weighted average of the four texture elements that are closest to the specified texture coordinates) to produce a texture value.     `NEAREST_MIPMAP_LINEAR`     Chooses the two mipmaps that most closely match the size of the pixel being textured and uses the `NEAREST` criterion (the texture element closest to the specified texture coordinates ) to produce a texture value from each mipmap. The final texture value is a weighted average of those two values.     `LINEAR_MIPMAP_LINEAR`     Chooses the two mipmaps that most closely match the size of the pixel being textured and uses the `LINEAR` criterion (a weighted average of the texture elements that are closest to the specified texture coordinates) to produce a texture value from each mipmap. The final texture value is a weighted average of those two values.        As more texture elements are sampled in the minification process, fewer aliasing artifacts will be apparent. While the `NEAREST` and `LINEAR` minification functions can be faster than the other four, they sample only one or multiple texture elements to determine the texture value of the pixel being rendered and can produce moire patterns or ragged transitions. The initial value of `TEXTURE_MIN_FILTER` is `NEAREST_MIPMAP_LINEAR`.
	
	- `TEXTURE_MAG_FILTER`: The texture magnification function is used whenever the level-of-detail function used when sampling from the texture determines that the texture should be magified. It sets the texture magnification function to either `NEAREST` or `LINEAR` (see below). `NEAREST` is generally faster than `LINEAR`, but it can produce textured images with sharper edges because the transition between texture elements is not as smooth. The initial value of `TEXTURE_MAG_FILTER` is `LINEAR`.      `NEAREST`     Returns the value of the texture element that is nearest (in Manhattan distance) to the specified texture coordinates.     `LINEAR`     Returns the weighted average of the texture elements that are closest to the specified texture coordinates. These can include items wrapped or repeated from other parts of a texture, depending on the values of `TEXTURE_WRAP_S` and `TEXTURE_WRAP_T`, and on the exact mapping.
	
	- `TEXTURE_MIN_LOD`: Sets the minimum level-of-detail parameter. This floating-point value limits the selection of highest resolution mipmap (lowest mipmap level). The initial value is -1000.
	
	- `TEXTURE_MAX_LOD`: Sets the maximum level-of-detail parameter. This floating-point value limits the selection of the lowest resolution mipmap (highest mipmap level). The initial value is 1000.
	
	- `TEXTURE_MAX_LEVEL`: Sets the index of the highest defined mipmap level. This is an integer value. The initial value is 1000.
	
	- `TEXTURE_SWIZZLE_R`: Sets the swizzle that will be applied to the r component of a texel before it is returned to the shader. Valid values for $(I `param`) are `RED`, `GREEN`, `BLUE`, `ALPHA`, `ZERO` and `ONE`. If `TEXTURE_SWIZZLE_R` is `RED`, the value for r will be taken from the first channel of the fetched texel. If `TEXTURE_SWIZZLE_R` is `GREEN`, the value for r will be taken from the second channel of the fetched texel. If `TEXTURE_SWIZZLE_R` is `BLUE`, the value for r will be taken from the third channel of the fetched texel. If `TEXTURE_SWIZZLE_R` is `ALPHA`, the value for r will be taken from the fourth channel of the fetched texel. If `TEXTURE_SWIZZLE_R` is `ZERO`, the value for r will be subtituted with 0.0. If `TEXTURE_SWIZZLE_R` is `ONE`, the value for r will be subtituted with 1.0. The initial value is `RED`.
	
	- `TEXTURE_SWIZZLE_G`: Sets the swizzle that will be applied to the g component of a texel before it is returned to the shader. Valid values for $(I `param`) and their effects are similar to those of `TEXTURE_SWIZZLE_R`. The initial value is `GREEN`.
	
	- `TEXTURE_SWIZZLE_B`: Sets the swizzle that will be applied to the b component of a texel before it is returned to the shader. Valid values for $(I `param`) and their effects are similar to those of `TEXTURE_SWIZZLE_R`. The initial value is `BLUE`.
	
	- `TEXTURE_SWIZZLE_A`: Sets the swizzle that will be applied to the a component of a texel before it is returned to the shader. Valid values for $(I `param`) and their effects are similar to those of `TEXTURE_SWIZZLE_R`. The initial value is `ALPHA`.
	
	- `TEXTURE_SWIZZLE_RGBA`: Sets the swizzles that will be applied to the r, g, b, and a components of a texel before they are returned to the shader. Valid values for $(I `params`) and their effects are similar to those of `TEXTURE_SWIZZLE_R`, except that all channels are specified simultaneously. Setting the value of `TEXTURE_SWIZZLE_RGBA` is equivalent (assuming no errors are generated) to setting the parameters of each of `TEXTURE_SWIZZLE_R`, `TEXTURE_SWIZZLE_G`, `TEXTURE_SWIZZLE_B`, and `TEXTURE_SWIZZLE_A` successively.
	
	- `TEXTURE_WRAP_S`: Sets the wrap parameter for texture coordinate s to either `CLAMP_TO_EDGE`, `CLAMP_TO_BORDER`, `MIRRORED_REPEAT`, `REPEAT`, or `MIRROR_CLAMP_TO_EDGE`. `CLAMP_TO_EDGE` causes s coordinates to be clamped to the range      1  2N      1 -    1  2N       , where N is the size of the texture in the direction of clamping. `CLAMP_TO_BORDER` evaluates s coordinates in a similar manner to `CLAMP_TO_EDGE`. However, in cases where clamping would have occurred in `CLAMP_TO_EDGE` mode, the fetched texel data is substituted with the values specified by `TEXTURE_BORDER_COLOR`. `REPEAT` causes the integer part of the s coordinate to be ignored; the GL uses only the fractional part, thereby creating a repeating pattern. `MIRRORED_REPEAT` causes the s coordinate to be set to the fractional part of the texture coordinate if the integer part of s is even; if the integer part of s is odd, then the s texture coordinate is set to   1 -  frac ⁡  s    , where   frac ⁡  s    represents the fractional part of s. `MIRROR_CLAMP_TO_EDGE` causes the s coordinate to be repeated as for `MIRRORED_REPEAT` for one repetition of the texture, at which point the coordinate to be clamped as in `CLAMP_TO_EDGE`. Initially, `TEXTURE_WRAP_S` is set to `REPEAT`.
	
	- `TEXTURE_WRAP_T`: Sets the wrap parameter for texture coordinate t to either `CLAMP_TO_EDGE`, `CLAMP_TO_BORDER`, `MIRRORED_REPEAT`, `REPEAT`, or `MIRROR_CLAMP_TO_EDGE`. See the discussion under `TEXTURE_WRAP_S`. Initially, `TEXTURE_WRAP_T` is set to `REPEAT`.
	
	- `TEXTURE_WRAP_R`: Sets the wrap parameter for texture coordinate r to either `CLAMP_TO_EDGE`, `CLAMP_TO_BORDER`, `MIRRORED_REPEAT`, `REPEAT`, or `MIRROR_CLAMP_TO_EDGE`. See the discussion under `TEXTURE_WRAP_S`. Initially, `TEXTURE_WRAP_R` is set to `REPEAT`.
	
	Params:
	target = Specifies the target to which the texture is bound for $(REF texParameter) functions. Must be one of `TEXTURE_1D`, `TEXTURE_1D_ARRAY`, `TEXTURE_2D`, `TEXTURE_2D_ARRAY`, `TEXTURE_2D_MULTISAMPLE`, `TEXTURE_2D_MULTISAMPLE_ARRAY`, `TEXTURE_3D`, `TEXTURE_CUBE_MAP`, `TEXTURE_CUBE_MAP_ARRAY`, or `TEXTURE_RECTANGLE`.
	pname = Specifies the symbolic name of a single-valued texture parameter. $(I `pname`) can be one of the following: `DEPTH_STENCIL_TEXTURE_MODE`, `TEXTURE_BASE_LEVEL`, `TEXTURE_COMPARE_FUNC`, `TEXTURE_COMPARE_MODE`, `TEXTURE_LOD_BIAS`, `TEXTURE_MIN_FILTER`, `TEXTURE_MAG_FILTER`, `TEXTURE_MIN_LOD`, `TEXTURE_MAX_LOD`, `TEXTURE_MAX_LEVEL`, `TEXTURE_SWIZZLE_R`, `TEXTURE_SWIZZLE_G`, `TEXTURE_SWIZZLE_B`, `TEXTURE_SWIZZLE_A`, `TEXTURE_WRAP_S`, `TEXTURE_WRAP_T`, or `TEXTURE_WRAP_R`.
	
	For the vector commands ($(REF texParameter*v)), $(I `pname`) can also be one of `TEXTURE_BORDER_COLOR` or `TEXTURE_SWIZZLE_RGBA`.
	param = For the scalar commands, specifies the value of $(I `pname`).
	*/
	void texParameterf(Enum target, Enum pname, Float param);
	
	/**
	$(REF texParameter) and $(REF textureParameter) assign the value or values in $(I `params`) to the texture parameter specified as $(I `pname`). For $(REF texParameter), $(I `target`) defines the target texture, either `TEXTURE_1D`, `TEXTURE_1D_ARRAY`, `TEXTURE_2D`, `TEXTURE_2D_ARRAY`, `TEXTURE_2D_MULTISAMPLE`, `TEXTURE_2D_MULTISAMPLE_ARRAY`, `TEXTURE_3D`, `TEXTURE_CUBE_MAP`, `TEXTURE_CUBE_MAP_ARRAY`, or `TEXTURE_RECTANGLE`. The following symbols are accepted in $(I `pname`):
	
	- `DEPTH_STENCIL_TEXTURE_MODE`: Specifies the mode used to read from depth-stencil format textures. $(I `params`) must be one of `DEPTH_COMPONENT` or `STENCIL_INDEX`. If the depth stencil mode is `DEPTH_COMPONENT`, then reads from depth-stencil format textures will return the depth component of the texel in Rt and the stencil component will be discarded. If the depth stencil mode is `STENCIL_INDEX` then the stencil component is returned in Rt and the depth component is discarded. The initial value is `DEPTH_COMPONENT`.
	
	- `TEXTURE_BASE_LEVEL`: Specifies the index of the lowest defined mipmap level. This is an integer value. The initial value is 0.
	
	- `TEXTURE_BORDER_COLOR`: The data in $(I `params`) specifies four values that define the border values that should be used for border texels. If a texel is sampled from the border of the texture, the values of `TEXTURE_BORDER_COLOR` are interpreted as an RGBA color to match the texture's internal format and substituted for the non-existent texel data. If the texture contains depth components, the first component of `TEXTURE_BORDER_COLOR` is interpreted as a depth value. The initial value is     0.0 , 0.0 , 0.0 , 0.0    .   If the values for `TEXTURE_BORDER_COLOR` are specified with $(REF texParameterIiv) or $(REF texParameterIuiv), the values are stored unmodified with an internal data type of integer. If specified with $(REF texParameteriv), they are converted to floating point with the following equation:   f =   2 c + 1    2 b  - 1    . If specified with $(REF texParameterfv), they are stored unmodified as floating-point values.
	
	- `TEXTURE_COMPARE_FUNC`: Specifies the comparison operator used when `TEXTURE_COMPARE_MODE` is set to `COMPARE_REF_TO_TEXTURE`. Permissible values are:           $(B  Texture Comparison Function )   $(B  Computed result )       `LEQUAL`     result =     1.0   0.0   ⁢     r <=  D t       r >  D t              `GEQUAL`     result =     1.0   0.0   ⁢     r >=  D t       r <  D t              `LESS`     result =     1.0   0.0   ⁢     r <  D t       r >=  D t              `GREATER`     result =     1.0   0.0   ⁢     r >  D t       r <=  D t              `EQUAL`     result =     1.0   0.0   ⁢     r =  D t       r ≠  D t              `NOTEQUAL`     result =     1.0   0.0   ⁢     r ≠  D t       r =  D t              `ALWAYS`     result = 1.0       `NEVER`     result = 0.0         where r is the current interpolated texture coordinate, and  D t   is the depth texture value sampled from the currently bound depth texture. result is assigned to the red channel.
	
	- `TEXTURE_COMPARE_MODE`: Specifies the texture comparison mode for currently bound depth textures. That is, a texture whose internal format is `DEPTH_COMPONENT_*`; see $(REF texImage2D)) Permissible values are:      `COMPARE_REF_TO_TEXTURE`     Specifies that the interpolated and clamped r texture coordinate should be compared to the value in the currently bound depth texture. See the discussion of `TEXTURE_COMPARE_FUNC` for details of how the comparison is evaluated. The result of the comparison is assigned to the red channel.     `NONE`     Specifies that the red channel should be assigned the appropriate value from the currently bound depth texture.
	
	- `TEXTURE_LOD_BIAS`: $(I `params`) specifies a fixed bias value that is to be added to the level-of-detail parameter for the texture before texture sampling. The specified value is added to the shader-supplied bias value (if any) and subsequently clamped into the implementation-defined range     -  bias max        bias max      , where   bias max    is the value of the implementation defined constant `MAX_TEXTURE_LOD_BIAS`. The initial value is 0.0.
	
	- `TEXTURE_MIN_FILTER`: The texture minifying function is used whenever the level-of-detail function used when sampling from the texture determines that the texture should be minified. There are six defined minifying functions. Two of them use either the nearest texture elements or a weighted average of multiple texture elements to compute the texture value. The other four use mipmaps.   A mipmap is an ordered set of arrays representing the same image at progressively lower resolutions. If the texture has dimensions   2 n  × 2 m   , there are    max ⁡  n m   + 1   mipmaps. The first mipmap is the original texture, with dimensions   2 n  × 2 m   . Each subsequent mipmap has dimensions   2   k - 1    × 2   l - 1     , where   2 k  × 2 l    are the dimensions of the previous mipmap, until either   k = 0   or   l = 0  . At that point, subsequent mipmaps have dimension   1 × 2   l - 1      or   2   k - 1    × 1   until the final mipmap, which has dimension   1 × 1  . To define the mipmaps, call $(REF texImage1D), $(REF texImage2D), $(REF texImage3D), $(REF copyTexImage1D), or $(REF copyTexImage2D) with the $(I level) argument indicating the order of the mipmaps. Level 0 is the original texture; level   max ⁡  n m    is the final   1 × 1   mipmap.   $(I `params`) supplies a function for minifying the texture as one of the following:      `NEAREST`     Returns the value of the texture element that is nearest (in Manhattan distance) to the specified texture coordinates.     `LINEAR`     Returns the weighted average of the four texture elements that are closest to the specified texture coordinates. These can include items wrapped or repeated from other parts of a texture, depending on the values of `TEXTURE_WRAP_S` and `TEXTURE_WRAP_T`, and on the exact mapping.     `NEAREST_MIPMAP_NEAREST`     Chooses the mipmap that most closely matches the size of the pixel being textured and uses the `NEAREST` criterion (the texture element closest to the specified texture coordinates) to produce a texture value.     `LINEAR_MIPMAP_NEAREST`     Chooses the mipmap that most closely matches the size of the pixel being textured and uses the `LINEAR` criterion (a weighted average of the four texture elements that are closest to the specified texture coordinates) to produce a texture value.     `NEAREST_MIPMAP_LINEAR`     Chooses the two mipmaps that most closely match the size of the pixel being textured and uses the `NEAREST` criterion (the texture element closest to the specified texture coordinates ) to produce a texture value from each mipmap. The final texture value is a weighted average of those two values.     `LINEAR_MIPMAP_LINEAR`     Chooses the two mipmaps that most closely match the size of the pixel being textured and uses the `LINEAR` criterion (a weighted average of the texture elements that are closest to the specified texture coordinates) to produce a texture value from each mipmap. The final texture value is a weighted average of those two values.        As more texture elements are sampled in the minification process, fewer aliasing artifacts will be apparent. While the `NEAREST` and `LINEAR` minification functions can be faster than the other four, they sample only one or multiple texture elements to determine the texture value of the pixel being rendered and can produce moire patterns or ragged transitions. The initial value of `TEXTURE_MIN_FILTER` is `NEAREST_MIPMAP_LINEAR`.
	
	- `TEXTURE_MAG_FILTER`: The texture magnification function is used whenever the level-of-detail function used when sampling from the texture determines that the texture should be magified. It sets the texture magnification function to either `NEAREST` or `LINEAR` (see below). `NEAREST` is generally faster than `LINEAR`, but it can produce textured images with sharper edges because the transition between texture elements is not as smooth. The initial value of `TEXTURE_MAG_FILTER` is `LINEAR`.      `NEAREST`     Returns the value of the texture element that is nearest (in Manhattan distance) to the specified texture coordinates.     `LINEAR`     Returns the weighted average of the texture elements that are closest to the specified texture coordinates. These can include items wrapped or repeated from other parts of a texture, depending on the values of `TEXTURE_WRAP_S` and `TEXTURE_WRAP_T`, and on the exact mapping.
	
	- `TEXTURE_MIN_LOD`: Sets the minimum level-of-detail parameter. This floating-point value limits the selection of highest resolution mipmap (lowest mipmap level). The initial value is -1000.
	
	- `TEXTURE_MAX_LOD`: Sets the maximum level-of-detail parameter. This floating-point value limits the selection of the lowest resolution mipmap (highest mipmap level). The initial value is 1000.
	
	- `TEXTURE_MAX_LEVEL`: Sets the index of the highest defined mipmap level. This is an integer value. The initial value is 1000.
	
	- `TEXTURE_SWIZZLE_R`: Sets the swizzle that will be applied to the r component of a texel before it is returned to the shader. Valid values for $(I `param`) are `RED`, `GREEN`, `BLUE`, `ALPHA`, `ZERO` and `ONE`. If `TEXTURE_SWIZZLE_R` is `RED`, the value for r will be taken from the first channel of the fetched texel. If `TEXTURE_SWIZZLE_R` is `GREEN`, the value for r will be taken from the second channel of the fetched texel. If `TEXTURE_SWIZZLE_R` is `BLUE`, the value for r will be taken from the third channel of the fetched texel. If `TEXTURE_SWIZZLE_R` is `ALPHA`, the value for r will be taken from the fourth channel of the fetched texel. If `TEXTURE_SWIZZLE_R` is `ZERO`, the value for r will be subtituted with 0.0. If `TEXTURE_SWIZZLE_R` is `ONE`, the value for r will be subtituted with 1.0. The initial value is `RED`.
	
	- `TEXTURE_SWIZZLE_G`: Sets the swizzle that will be applied to the g component of a texel before it is returned to the shader. Valid values for $(I `param`) and their effects are similar to those of `TEXTURE_SWIZZLE_R`. The initial value is `GREEN`.
	
	- `TEXTURE_SWIZZLE_B`: Sets the swizzle that will be applied to the b component of a texel before it is returned to the shader. Valid values for $(I `param`) and their effects are similar to those of `TEXTURE_SWIZZLE_R`. The initial value is `BLUE`.
	
	- `TEXTURE_SWIZZLE_A`: Sets the swizzle that will be applied to the a component of a texel before it is returned to the shader. Valid values for $(I `param`) and their effects are similar to those of `TEXTURE_SWIZZLE_R`. The initial value is `ALPHA`.
	
	- `TEXTURE_SWIZZLE_RGBA`: Sets the swizzles that will be applied to the r, g, b, and a components of a texel before they are returned to the shader. Valid values for $(I `params`) and their effects are similar to those of `TEXTURE_SWIZZLE_R`, except that all channels are specified simultaneously. Setting the value of `TEXTURE_SWIZZLE_RGBA` is equivalent (assuming no errors are generated) to setting the parameters of each of `TEXTURE_SWIZZLE_R`, `TEXTURE_SWIZZLE_G`, `TEXTURE_SWIZZLE_B`, and `TEXTURE_SWIZZLE_A` successively.
	
	- `TEXTURE_WRAP_S`: Sets the wrap parameter for texture coordinate s to either `CLAMP_TO_EDGE`, `CLAMP_TO_BORDER`, `MIRRORED_REPEAT`, `REPEAT`, or `MIRROR_CLAMP_TO_EDGE`. `CLAMP_TO_EDGE` causes s coordinates to be clamped to the range      1  2N      1 -    1  2N       , where N is the size of the texture in the direction of clamping. `CLAMP_TO_BORDER` evaluates s coordinates in a similar manner to `CLAMP_TO_EDGE`. However, in cases where clamping would have occurred in `CLAMP_TO_EDGE` mode, the fetched texel data is substituted with the values specified by `TEXTURE_BORDER_COLOR`. `REPEAT` causes the integer part of the s coordinate to be ignored; the GL uses only the fractional part, thereby creating a repeating pattern. `MIRRORED_REPEAT` causes the s coordinate to be set to the fractional part of the texture coordinate if the integer part of s is even; if the integer part of s is odd, then the s texture coordinate is set to   1 -  frac ⁡  s    , where   frac ⁡  s    represents the fractional part of s. `MIRROR_CLAMP_TO_EDGE` causes the s coordinate to be repeated as for `MIRRORED_REPEAT` for one repetition of the texture, at which point the coordinate to be clamped as in `CLAMP_TO_EDGE`. Initially, `TEXTURE_WRAP_S` is set to `REPEAT`.
	
	- `TEXTURE_WRAP_T`: Sets the wrap parameter for texture coordinate t to either `CLAMP_TO_EDGE`, `CLAMP_TO_BORDER`, `MIRRORED_REPEAT`, `REPEAT`, or `MIRROR_CLAMP_TO_EDGE`. See the discussion under `TEXTURE_WRAP_S`. Initially, `TEXTURE_WRAP_T` is set to `REPEAT`.
	
	- `TEXTURE_WRAP_R`: Sets the wrap parameter for texture coordinate r to either `CLAMP_TO_EDGE`, `CLAMP_TO_BORDER`, `MIRRORED_REPEAT`, `REPEAT`, or `MIRROR_CLAMP_TO_EDGE`. See the discussion under `TEXTURE_WRAP_S`. Initially, `TEXTURE_WRAP_R` is set to `REPEAT`.
	
	Params:
	target = Specifies the target to which the texture is bound for $(REF texParameter) functions. Must be one of `TEXTURE_1D`, `TEXTURE_1D_ARRAY`, `TEXTURE_2D`, `TEXTURE_2D_ARRAY`, `TEXTURE_2D_MULTISAMPLE`, `TEXTURE_2D_MULTISAMPLE_ARRAY`, `TEXTURE_3D`, `TEXTURE_CUBE_MAP`, `TEXTURE_CUBE_MAP_ARRAY`, or `TEXTURE_RECTANGLE`.
	pname = Specifies the symbolic name of a single-valued texture parameter. $(I `pname`) can be one of the following: `DEPTH_STENCIL_TEXTURE_MODE`, `TEXTURE_BASE_LEVEL`, `TEXTURE_COMPARE_FUNC`, `TEXTURE_COMPARE_MODE`, `TEXTURE_LOD_BIAS`, `TEXTURE_MIN_FILTER`, `TEXTURE_MAG_FILTER`, `TEXTURE_MIN_LOD`, `TEXTURE_MAX_LOD`, `TEXTURE_MAX_LEVEL`, `TEXTURE_SWIZZLE_R`, `TEXTURE_SWIZZLE_G`, `TEXTURE_SWIZZLE_B`, `TEXTURE_SWIZZLE_A`, `TEXTURE_WRAP_S`, `TEXTURE_WRAP_T`, or `TEXTURE_WRAP_R`.
	
	For the vector commands ($(REF texParameter*v)), $(I `pname`) can also be one of `TEXTURE_BORDER_COLOR` or `TEXTURE_SWIZZLE_RGBA`.
	params = For the vector commands, specifies a pointer to an array where the value or values of $(I `pname`) are stored.
	*/
	void texParameterfv(Enum target, Enum pname, const(Float)* params);
	
	/**
	$(REF texParameter) and $(REF textureParameter) assign the value or values in $(I `params`) to the texture parameter specified as $(I `pname`). For $(REF texParameter), $(I `target`) defines the target texture, either `TEXTURE_1D`, `TEXTURE_1D_ARRAY`, `TEXTURE_2D`, `TEXTURE_2D_ARRAY`, `TEXTURE_2D_MULTISAMPLE`, `TEXTURE_2D_MULTISAMPLE_ARRAY`, `TEXTURE_3D`, `TEXTURE_CUBE_MAP`, `TEXTURE_CUBE_MAP_ARRAY`, or `TEXTURE_RECTANGLE`. The following symbols are accepted in $(I `pname`):
	
	- `DEPTH_STENCIL_TEXTURE_MODE`: Specifies the mode used to read from depth-stencil format textures. $(I `params`) must be one of `DEPTH_COMPONENT` or `STENCIL_INDEX`. If the depth stencil mode is `DEPTH_COMPONENT`, then reads from depth-stencil format textures will return the depth component of the texel in Rt and the stencil component will be discarded. If the depth stencil mode is `STENCIL_INDEX` then the stencil component is returned in Rt and the depth component is discarded. The initial value is `DEPTH_COMPONENT`.
	
	- `TEXTURE_BASE_LEVEL`: Specifies the index of the lowest defined mipmap level. This is an integer value. The initial value is 0.
	
	- `TEXTURE_BORDER_COLOR`: The data in $(I `params`) specifies four values that define the border values that should be used for border texels. If a texel is sampled from the border of the texture, the values of `TEXTURE_BORDER_COLOR` are interpreted as an RGBA color to match the texture's internal format and substituted for the non-existent texel data. If the texture contains depth components, the first component of `TEXTURE_BORDER_COLOR` is interpreted as a depth value. The initial value is     0.0 , 0.0 , 0.0 , 0.0    .   If the values for `TEXTURE_BORDER_COLOR` are specified with $(REF texParameterIiv) or $(REF texParameterIuiv), the values are stored unmodified with an internal data type of integer. If specified with $(REF texParameteriv), they are converted to floating point with the following equation:   f =   2 c + 1    2 b  - 1    . If specified with $(REF texParameterfv), they are stored unmodified as floating-point values.
	
	- `TEXTURE_COMPARE_FUNC`: Specifies the comparison operator used when `TEXTURE_COMPARE_MODE` is set to `COMPARE_REF_TO_TEXTURE`. Permissible values are:           $(B  Texture Comparison Function )   $(B  Computed result )       `LEQUAL`     result =     1.0   0.0   ⁢     r <=  D t       r >  D t              `GEQUAL`     result =     1.0   0.0   ⁢     r >=  D t       r <  D t              `LESS`     result =     1.0   0.0   ⁢     r <  D t       r >=  D t              `GREATER`     result =     1.0   0.0   ⁢     r >  D t       r <=  D t              `EQUAL`     result =     1.0   0.0   ⁢     r =  D t       r ≠  D t              `NOTEQUAL`     result =     1.0   0.0   ⁢     r ≠  D t       r =  D t              `ALWAYS`     result = 1.0       `NEVER`     result = 0.0         where r is the current interpolated texture coordinate, and  D t   is the depth texture value sampled from the currently bound depth texture. result is assigned to the red channel.
	
	- `TEXTURE_COMPARE_MODE`: Specifies the texture comparison mode for currently bound depth textures. That is, a texture whose internal format is `DEPTH_COMPONENT_*`; see $(REF texImage2D)) Permissible values are:      `COMPARE_REF_TO_TEXTURE`     Specifies that the interpolated and clamped r texture coordinate should be compared to the value in the currently bound depth texture. See the discussion of `TEXTURE_COMPARE_FUNC` for details of how the comparison is evaluated. The result of the comparison is assigned to the red channel.     `NONE`     Specifies that the red channel should be assigned the appropriate value from the currently bound depth texture.
	
	- `TEXTURE_LOD_BIAS`: $(I `params`) specifies a fixed bias value that is to be added to the level-of-detail parameter for the texture before texture sampling. The specified value is added to the shader-supplied bias value (if any) and subsequently clamped into the implementation-defined range     -  bias max        bias max      , where   bias max    is the value of the implementation defined constant `MAX_TEXTURE_LOD_BIAS`. The initial value is 0.0.
	
	- `TEXTURE_MIN_FILTER`: The texture minifying function is used whenever the level-of-detail function used when sampling from the texture determines that the texture should be minified. There are six defined minifying functions. Two of them use either the nearest texture elements or a weighted average of multiple texture elements to compute the texture value. The other four use mipmaps.   A mipmap is an ordered set of arrays representing the same image at progressively lower resolutions. If the texture has dimensions   2 n  × 2 m   , there are    max ⁡  n m   + 1   mipmaps. The first mipmap is the original texture, with dimensions   2 n  × 2 m   . Each subsequent mipmap has dimensions   2   k - 1    × 2   l - 1     , where   2 k  × 2 l    are the dimensions of the previous mipmap, until either   k = 0   or   l = 0  . At that point, subsequent mipmaps have dimension   1 × 2   l - 1      or   2   k - 1    × 1   until the final mipmap, which has dimension   1 × 1  . To define the mipmaps, call $(REF texImage1D), $(REF texImage2D), $(REF texImage3D), $(REF copyTexImage1D), or $(REF copyTexImage2D) with the $(I level) argument indicating the order of the mipmaps. Level 0 is the original texture; level   max ⁡  n m    is the final   1 × 1   mipmap.   $(I `params`) supplies a function for minifying the texture as one of the following:      `NEAREST`     Returns the value of the texture element that is nearest (in Manhattan distance) to the specified texture coordinates.     `LINEAR`     Returns the weighted average of the four texture elements that are closest to the specified texture coordinates. These can include items wrapped or repeated from other parts of a texture, depending on the values of `TEXTURE_WRAP_S` and `TEXTURE_WRAP_T`, and on the exact mapping.     `NEAREST_MIPMAP_NEAREST`     Chooses the mipmap that most closely matches the size of the pixel being textured and uses the `NEAREST` criterion (the texture element closest to the specified texture coordinates) to produce a texture value.     `LINEAR_MIPMAP_NEAREST`     Chooses the mipmap that most closely matches the size of the pixel being textured and uses the `LINEAR` criterion (a weighted average of the four texture elements that are closest to the specified texture coordinates) to produce a texture value.     `NEAREST_MIPMAP_LINEAR`     Chooses the two mipmaps that most closely match the size of the pixel being textured and uses the `NEAREST` criterion (the texture element closest to the specified texture coordinates ) to produce a texture value from each mipmap. The final texture value is a weighted average of those two values.     `LINEAR_MIPMAP_LINEAR`     Chooses the two mipmaps that most closely match the size of the pixel being textured and uses the `LINEAR` criterion (a weighted average of the texture elements that are closest to the specified texture coordinates) to produce a texture value from each mipmap. The final texture value is a weighted average of those two values.        As more texture elements are sampled in the minification process, fewer aliasing artifacts will be apparent. While the `NEAREST` and `LINEAR` minification functions can be faster than the other four, they sample only one or multiple texture elements to determine the texture value of the pixel being rendered and can produce moire patterns or ragged transitions. The initial value of `TEXTURE_MIN_FILTER` is `NEAREST_MIPMAP_LINEAR`.
	
	- `TEXTURE_MAG_FILTER`: The texture magnification function is used whenever the level-of-detail function used when sampling from the texture determines that the texture should be magified. It sets the texture magnification function to either `NEAREST` or `LINEAR` (see below). `NEAREST` is generally faster than `LINEAR`, but it can produce textured images with sharper edges because the transition between texture elements is not as smooth. The initial value of `TEXTURE_MAG_FILTER` is `LINEAR`.      `NEAREST`     Returns the value of the texture element that is nearest (in Manhattan distance) to the specified texture coordinates.     `LINEAR`     Returns the weighted average of the texture elements that are closest to the specified texture coordinates. These can include items wrapped or repeated from other parts of a texture, depending on the values of `TEXTURE_WRAP_S` and `TEXTURE_WRAP_T`, and on the exact mapping.
	
	- `TEXTURE_MIN_LOD`: Sets the minimum level-of-detail parameter. This floating-point value limits the selection of highest resolution mipmap (lowest mipmap level). The initial value is -1000.
	
	- `TEXTURE_MAX_LOD`: Sets the maximum level-of-detail parameter. This floating-point value limits the selection of the lowest resolution mipmap (highest mipmap level). The initial value is 1000.
	
	- `TEXTURE_MAX_LEVEL`: Sets the index of the highest defined mipmap level. This is an integer value. The initial value is 1000.
	
	- `TEXTURE_SWIZZLE_R`: Sets the swizzle that will be applied to the r component of a texel before it is returned to the shader. Valid values for $(I `param`) are `RED`, `GREEN`, `BLUE`, `ALPHA`, `ZERO` and `ONE`. If `TEXTURE_SWIZZLE_R` is `RED`, the value for r will be taken from the first channel of the fetched texel. If `TEXTURE_SWIZZLE_R` is `GREEN`, the value for r will be taken from the second channel of the fetched texel. If `TEXTURE_SWIZZLE_R` is `BLUE`, the value for r will be taken from the third channel of the fetched texel. If `TEXTURE_SWIZZLE_R` is `ALPHA`, the value for r will be taken from the fourth channel of the fetched texel. If `TEXTURE_SWIZZLE_R` is `ZERO`, the value for r will be subtituted with 0.0. If `TEXTURE_SWIZZLE_R` is `ONE`, the value for r will be subtituted with 1.0. The initial value is `RED`.
	
	- `TEXTURE_SWIZZLE_G`: Sets the swizzle that will be applied to the g component of a texel before it is returned to the shader. Valid values for $(I `param`) and their effects are similar to those of `TEXTURE_SWIZZLE_R`. The initial value is `GREEN`.
	
	- `TEXTURE_SWIZZLE_B`: Sets the swizzle that will be applied to the b component of a texel before it is returned to the shader. Valid values for $(I `param`) and their effects are similar to those of `TEXTURE_SWIZZLE_R`. The initial value is `BLUE`.
	
	- `TEXTURE_SWIZZLE_A`: Sets the swizzle that will be applied to the a component of a texel before it is returned to the shader. Valid values for $(I `param`) and their effects are similar to those of `TEXTURE_SWIZZLE_R`. The initial value is `ALPHA`.
	
	- `TEXTURE_SWIZZLE_RGBA`: Sets the swizzles that will be applied to the r, g, b, and a components of a texel before they are returned to the shader. Valid values for $(I `params`) and their effects are similar to those of `TEXTURE_SWIZZLE_R`, except that all channels are specified simultaneously. Setting the value of `TEXTURE_SWIZZLE_RGBA` is equivalent (assuming no errors are generated) to setting the parameters of each of `TEXTURE_SWIZZLE_R`, `TEXTURE_SWIZZLE_G`, `TEXTURE_SWIZZLE_B`, and `TEXTURE_SWIZZLE_A` successively.
	
	- `TEXTURE_WRAP_S`: Sets the wrap parameter for texture coordinate s to either `CLAMP_TO_EDGE`, `CLAMP_TO_BORDER`, `MIRRORED_REPEAT`, `REPEAT`, or `MIRROR_CLAMP_TO_EDGE`. `CLAMP_TO_EDGE` causes s coordinates to be clamped to the range      1  2N      1 -    1  2N       , where N is the size of the texture in the direction of clamping. `CLAMP_TO_BORDER` evaluates s coordinates in a similar manner to `CLAMP_TO_EDGE`. However, in cases where clamping would have occurred in `CLAMP_TO_EDGE` mode, the fetched texel data is substituted with the values specified by `TEXTURE_BORDER_COLOR`. `REPEAT` causes the integer part of the s coordinate to be ignored; the GL uses only the fractional part, thereby creating a repeating pattern. `MIRRORED_REPEAT` causes the s coordinate to be set to the fractional part of the texture coordinate if the integer part of s is even; if the integer part of s is odd, then the s texture coordinate is set to   1 -  frac ⁡  s    , where   frac ⁡  s    represents the fractional part of s. `MIRROR_CLAMP_TO_EDGE` causes the s coordinate to be repeated as for `MIRRORED_REPEAT` for one repetition of the texture, at which point the coordinate to be clamped as in `CLAMP_TO_EDGE`. Initially, `TEXTURE_WRAP_S` is set to `REPEAT`.
	
	- `TEXTURE_WRAP_T`: Sets the wrap parameter for texture coordinate t to either `CLAMP_TO_EDGE`, `CLAMP_TO_BORDER`, `MIRRORED_REPEAT`, `REPEAT`, or `MIRROR_CLAMP_TO_EDGE`. See the discussion under `TEXTURE_WRAP_S`. Initially, `TEXTURE_WRAP_T` is set to `REPEAT`.
	
	- `TEXTURE_WRAP_R`: Sets the wrap parameter for texture coordinate r to either `CLAMP_TO_EDGE`, `CLAMP_TO_BORDER`, `MIRRORED_REPEAT`, `REPEAT`, or `MIRROR_CLAMP_TO_EDGE`. See the discussion under `TEXTURE_WRAP_S`. Initially, `TEXTURE_WRAP_R` is set to `REPEAT`.
	
	Params:
	target = Specifies the target to which the texture is bound for $(REF texParameter) functions. Must be one of `TEXTURE_1D`, `TEXTURE_1D_ARRAY`, `TEXTURE_2D`, `TEXTURE_2D_ARRAY`, `TEXTURE_2D_MULTISAMPLE`, `TEXTURE_2D_MULTISAMPLE_ARRAY`, `TEXTURE_3D`, `TEXTURE_CUBE_MAP`, `TEXTURE_CUBE_MAP_ARRAY`, or `TEXTURE_RECTANGLE`.
	pname = Specifies the symbolic name of a single-valued texture parameter. $(I `pname`) can be one of the following: `DEPTH_STENCIL_TEXTURE_MODE`, `TEXTURE_BASE_LEVEL`, `TEXTURE_COMPARE_FUNC`, `TEXTURE_COMPARE_MODE`, `TEXTURE_LOD_BIAS`, `TEXTURE_MIN_FILTER`, `TEXTURE_MAG_FILTER`, `TEXTURE_MIN_LOD`, `TEXTURE_MAX_LOD`, `TEXTURE_MAX_LEVEL`, `TEXTURE_SWIZZLE_R`, `TEXTURE_SWIZZLE_G`, `TEXTURE_SWIZZLE_B`, `TEXTURE_SWIZZLE_A`, `TEXTURE_WRAP_S`, `TEXTURE_WRAP_T`, or `TEXTURE_WRAP_R`.
	
	For the vector commands ($(REF texParameter*v)), $(I `pname`) can also be one of `TEXTURE_BORDER_COLOR` or `TEXTURE_SWIZZLE_RGBA`.
	param = For the scalar commands, specifies the value of $(I `pname`).
	*/
	void texParameteri(Enum target, Enum pname, Int param);
	
	/**
	$(REF texParameter) and $(REF textureParameter) assign the value or values in $(I `params`) to the texture parameter specified as $(I `pname`). For $(REF texParameter), $(I `target`) defines the target texture, either `TEXTURE_1D`, `TEXTURE_1D_ARRAY`, `TEXTURE_2D`, `TEXTURE_2D_ARRAY`, `TEXTURE_2D_MULTISAMPLE`, `TEXTURE_2D_MULTISAMPLE_ARRAY`, `TEXTURE_3D`, `TEXTURE_CUBE_MAP`, `TEXTURE_CUBE_MAP_ARRAY`, or `TEXTURE_RECTANGLE`. The following symbols are accepted in $(I `pname`):
	
	- `DEPTH_STENCIL_TEXTURE_MODE`: Specifies the mode used to read from depth-stencil format textures. $(I `params`) must be one of `DEPTH_COMPONENT` or `STENCIL_INDEX`. If the depth stencil mode is `DEPTH_COMPONENT`, then reads from depth-stencil format textures will return the depth component of the texel in Rt and the stencil component will be discarded. If the depth stencil mode is `STENCIL_INDEX` then the stencil component is returned in Rt and the depth component is discarded. The initial value is `DEPTH_COMPONENT`.
	
	- `TEXTURE_BASE_LEVEL`: Specifies the index of the lowest defined mipmap level. This is an integer value. The initial value is 0.
	
	- `TEXTURE_BORDER_COLOR`: The data in $(I `params`) specifies four values that define the border values that should be used for border texels. If a texel is sampled from the border of the texture, the values of `TEXTURE_BORDER_COLOR` are interpreted as an RGBA color to match the texture's internal format and substituted for the non-existent texel data. If the texture contains depth components, the first component of `TEXTURE_BORDER_COLOR` is interpreted as a depth value. The initial value is     0.0 , 0.0 , 0.0 , 0.0    .   If the values for `TEXTURE_BORDER_COLOR` are specified with $(REF texParameterIiv) or $(REF texParameterIuiv), the values are stored unmodified with an internal data type of integer. If specified with $(REF texParameteriv), they are converted to floating point with the following equation:   f =   2 c + 1    2 b  - 1    . If specified with $(REF texParameterfv), they are stored unmodified as floating-point values.
	
	- `TEXTURE_COMPARE_FUNC`: Specifies the comparison operator used when `TEXTURE_COMPARE_MODE` is set to `COMPARE_REF_TO_TEXTURE`. Permissible values are:           $(B  Texture Comparison Function )   $(B  Computed result )       `LEQUAL`     result =     1.0   0.0   ⁢     r <=  D t       r >  D t              `GEQUAL`     result =     1.0   0.0   ⁢     r >=  D t       r <  D t              `LESS`     result =     1.0   0.0   ⁢     r <  D t       r >=  D t              `GREATER`     result =     1.0   0.0   ⁢     r >  D t       r <=  D t              `EQUAL`     result =     1.0   0.0   ⁢     r =  D t       r ≠  D t              `NOTEQUAL`     result =     1.0   0.0   ⁢     r ≠  D t       r =  D t              `ALWAYS`     result = 1.0       `NEVER`     result = 0.0         where r is the current interpolated texture coordinate, and  D t   is the depth texture value sampled from the currently bound depth texture. result is assigned to the red channel.
	
	- `TEXTURE_COMPARE_MODE`: Specifies the texture comparison mode for currently bound depth textures. That is, a texture whose internal format is `DEPTH_COMPONENT_*`; see $(REF texImage2D)) Permissible values are:      `COMPARE_REF_TO_TEXTURE`     Specifies that the interpolated and clamped r texture coordinate should be compared to the value in the currently bound depth texture. See the discussion of `TEXTURE_COMPARE_FUNC` for details of how the comparison is evaluated. The result of the comparison is assigned to the red channel.     `NONE`     Specifies that the red channel should be assigned the appropriate value from the currently bound depth texture.
	
	- `TEXTURE_LOD_BIAS`: $(I `params`) specifies a fixed bias value that is to be added to the level-of-detail parameter for the texture before texture sampling. The specified value is added to the shader-supplied bias value (if any) and subsequently clamped into the implementation-defined range     -  bias max        bias max      , where   bias max    is the value of the implementation defined constant `MAX_TEXTURE_LOD_BIAS`. The initial value is 0.0.
	
	- `TEXTURE_MIN_FILTER`: The texture minifying function is used whenever the level-of-detail function used when sampling from the texture determines that the texture should be minified. There are six defined minifying functions. Two of them use either the nearest texture elements or a weighted average of multiple texture elements to compute the texture value. The other four use mipmaps.   A mipmap is an ordered set of arrays representing the same image at progressively lower resolutions. If the texture has dimensions   2 n  × 2 m   , there are    max ⁡  n m   + 1   mipmaps. The first mipmap is the original texture, with dimensions   2 n  × 2 m   . Each subsequent mipmap has dimensions   2   k - 1    × 2   l - 1     , where   2 k  × 2 l    are the dimensions of the previous mipmap, until either   k = 0   or   l = 0  . At that point, subsequent mipmaps have dimension   1 × 2   l - 1      or   2   k - 1    × 1   until the final mipmap, which has dimension   1 × 1  . To define the mipmaps, call $(REF texImage1D), $(REF texImage2D), $(REF texImage3D), $(REF copyTexImage1D), or $(REF copyTexImage2D) with the $(I level) argument indicating the order of the mipmaps. Level 0 is the original texture; level   max ⁡  n m    is the final   1 × 1   mipmap.   $(I `params`) supplies a function for minifying the texture as one of the following:      `NEAREST`     Returns the value of the texture element that is nearest (in Manhattan distance) to the specified texture coordinates.     `LINEAR`     Returns the weighted average of the four texture elements that are closest to the specified texture coordinates. These can include items wrapped or repeated from other parts of a texture, depending on the values of `TEXTURE_WRAP_S` and `TEXTURE_WRAP_T`, and on the exact mapping.     `NEAREST_MIPMAP_NEAREST`     Chooses the mipmap that most closely matches the size of the pixel being textured and uses the `NEAREST` criterion (the texture element closest to the specified texture coordinates) to produce a texture value.     `LINEAR_MIPMAP_NEAREST`     Chooses the mipmap that most closely matches the size of the pixel being textured and uses the `LINEAR` criterion (a weighted average of the four texture elements that are closest to the specified texture coordinates) to produce a texture value.     `NEAREST_MIPMAP_LINEAR`     Chooses the two mipmaps that most closely match the size of the pixel being textured and uses the `NEAREST` criterion (the texture element closest to the specified texture coordinates ) to produce a texture value from each mipmap. The final texture value is a weighted average of those two values.     `LINEAR_MIPMAP_LINEAR`     Chooses the two mipmaps that most closely match the size of the pixel being textured and uses the `LINEAR` criterion (a weighted average of the texture elements that are closest to the specified texture coordinates) to produce a texture value from each mipmap. The final texture value is a weighted average of those two values.        As more texture elements are sampled in the minification process, fewer aliasing artifacts will be apparent. While the `NEAREST` and `LINEAR` minification functions can be faster than the other four, they sample only one or multiple texture elements to determine the texture value of the pixel being rendered and can produce moire patterns or ragged transitions. The initial value of `TEXTURE_MIN_FILTER` is `NEAREST_MIPMAP_LINEAR`.
	
	- `TEXTURE_MAG_FILTER`: The texture magnification function is used whenever the level-of-detail function used when sampling from the texture determines that the texture should be magified. It sets the texture magnification function to either `NEAREST` or `LINEAR` (see below). `NEAREST` is generally faster than `LINEAR`, but it can produce textured images with sharper edges because the transition between texture elements is not as smooth. The initial value of `TEXTURE_MAG_FILTER` is `LINEAR`.      `NEAREST`     Returns the value of the texture element that is nearest (in Manhattan distance) to the specified texture coordinates.     `LINEAR`     Returns the weighted average of the texture elements that are closest to the specified texture coordinates. These can include items wrapped or repeated from other parts of a texture, depending on the values of `TEXTURE_WRAP_S` and `TEXTURE_WRAP_T`, and on the exact mapping.
	
	- `TEXTURE_MIN_LOD`: Sets the minimum level-of-detail parameter. This floating-point value limits the selection of highest resolution mipmap (lowest mipmap level). The initial value is -1000.
	
	- `TEXTURE_MAX_LOD`: Sets the maximum level-of-detail parameter. This floating-point value limits the selection of the lowest resolution mipmap (highest mipmap level). The initial value is 1000.
	
	- `TEXTURE_MAX_LEVEL`: Sets the index of the highest defined mipmap level. This is an integer value. The initial value is 1000.
	
	- `TEXTURE_SWIZZLE_R`: Sets the swizzle that will be applied to the r component of a texel before it is returned to the shader. Valid values for $(I `param`) are `RED`, `GREEN`, `BLUE`, `ALPHA`, `ZERO` and `ONE`. If `TEXTURE_SWIZZLE_R` is `RED`, the value for r will be taken from the first channel of the fetched texel. If `TEXTURE_SWIZZLE_R` is `GREEN`, the value for r will be taken from the second channel of the fetched texel. If `TEXTURE_SWIZZLE_R` is `BLUE`, the value for r will be taken from the third channel of the fetched texel. If `TEXTURE_SWIZZLE_R` is `ALPHA`, the value for r will be taken from the fourth channel of the fetched texel. If `TEXTURE_SWIZZLE_R` is `ZERO`, the value for r will be subtituted with 0.0. If `TEXTURE_SWIZZLE_R` is `ONE`, the value for r will be subtituted with 1.0. The initial value is `RED`.
	
	- `TEXTURE_SWIZZLE_G`: Sets the swizzle that will be applied to the g component of a texel before it is returned to the shader. Valid values for $(I `param`) and their effects are similar to those of `TEXTURE_SWIZZLE_R`. The initial value is `GREEN`.
	
	- `TEXTURE_SWIZZLE_B`: Sets the swizzle that will be applied to the b component of a texel before it is returned to the shader. Valid values for $(I `param`) and their effects are similar to those of `TEXTURE_SWIZZLE_R`. The initial value is `BLUE`.
	
	- `TEXTURE_SWIZZLE_A`: Sets the swizzle that will be applied to the a component of a texel before it is returned to the shader. Valid values for $(I `param`) and their effects are similar to those of `TEXTURE_SWIZZLE_R`. The initial value is `ALPHA`.
	
	- `TEXTURE_SWIZZLE_RGBA`: Sets the swizzles that will be applied to the r, g, b, and a components of a texel before they are returned to the shader. Valid values for $(I `params`) and their effects are similar to those of `TEXTURE_SWIZZLE_R`, except that all channels are specified simultaneously. Setting the value of `TEXTURE_SWIZZLE_RGBA` is equivalent (assuming no errors are generated) to setting the parameters of each of `TEXTURE_SWIZZLE_R`, `TEXTURE_SWIZZLE_G`, `TEXTURE_SWIZZLE_B`, and `TEXTURE_SWIZZLE_A` successively.
	
	- `TEXTURE_WRAP_S`: Sets the wrap parameter for texture coordinate s to either `CLAMP_TO_EDGE`, `CLAMP_TO_BORDER`, `MIRRORED_REPEAT`, `REPEAT`, or `MIRROR_CLAMP_TO_EDGE`. `CLAMP_TO_EDGE` causes s coordinates to be clamped to the range      1  2N      1 -    1  2N       , where N is the size of the texture in the direction of clamping. `CLAMP_TO_BORDER` evaluates s coordinates in a similar manner to `CLAMP_TO_EDGE`. However, in cases where clamping would have occurred in `CLAMP_TO_EDGE` mode, the fetched texel data is substituted with the values specified by `TEXTURE_BORDER_COLOR`. `REPEAT` causes the integer part of the s coordinate to be ignored; the GL uses only the fractional part, thereby creating a repeating pattern. `MIRRORED_REPEAT` causes the s coordinate to be set to the fractional part of the texture coordinate if the integer part of s is even; if the integer part of s is odd, then the s texture coordinate is set to   1 -  frac ⁡  s    , where   frac ⁡  s    represents the fractional part of s. `MIRROR_CLAMP_TO_EDGE` causes the s coordinate to be repeated as for `MIRRORED_REPEAT` for one repetition of the texture, at which point the coordinate to be clamped as in `CLAMP_TO_EDGE`. Initially, `TEXTURE_WRAP_S` is set to `REPEAT`.
	
	- `TEXTURE_WRAP_T`: Sets the wrap parameter for texture coordinate t to either `CLAMP_TO_EDGE`, `CLAMP_TO_BORDER`, `MIRRORED_REPEAT`, `REPEAT`, or `MIRROR_CLAMP_TO_EDGE`. See the discussion under `TEXTURE_WRAP_S`. Initially, `TEXTURE_WRAP_T` is set to `REPEAT`.
	
	- `TEXTURE_WRAP_R`: Sets the wrap parameter for texture coordinate r to either `CLAMP_TO_EDGE`, `CLAMP_TO_BORDER`, `MIRRORED_REPEAT`, `REPEAT`, or `MIRROR_CLAMP_TO_EDGE`. See the discussion under `TEXTURE_WRAP_S`. Initially, `TEXTURE_WRAP_R` is set to `REPEAT`.
	
	Params:
	target = Specifies the target to which the texture is bound for $(REF texParameter) functions. Must be one of `TEXTURE_1D`, `TEXTURE_1D_ARRAY`, `TEXTURE_2D`, `TEXTURE_2D_ARRAY`, `TEXTURE_2D_MULTISAMPLE`, `TEXTURE_2D_MULTISAMPLE_ARRAY`, `TEXTURE_3D`, `TEXTURE_CUBE_MAP`, `TEXTURE_CUBE_MAP_ARRAY`, or `TEXTURE_RECTANGLE`.
	pname = Specifies the symbolic name of a single-valued texture parameter. $(I `pname`) can be one of the following: `DEPTH_STENCIL_TEXTURE_MODE`, `TEXTURE_BASE_LEVEL`, `TEXTURE_COMPARE_FUNC`, `TEXTURE_COMPARE_MODE`, `TEXTURE_LOD_BIAS`, `TEXTURE_MIN_FILTER`, `TEXTURE_MAG_FILTER`, `TEXTURE_MIN_LOD`, `TEXTURE_MAX_LOD`, `TEXTURE_MAX_LEVEL`, `TEXTURE_SWIZZLE_R`, `TEXTURE_SWIZZLE_G`, `TEXTURE_SWIZZLE_B`, `TEXTURE_SWIZZLE_A`, `TEXTURE_WRAP_S`, `TEXTURE_WRAP_T`, or `TEXTURE_WRAP_R`.
	
	For the vector commands ($(REF texParameter*v)), $(I `pname`) can also be one of `TEXTURE_BORDER_COLOR` or `TEXTURE_SWIZZLE_RGBA`.
	params = For the vector commands, specifies a pointer to an array where the value or values of $(I `pname`) are stored.
	*/
	void texParameteriv(Enum target, Enum pname, const(Int)* params);
	
	/**
	Texturing maps a portion of a specified texture image onto each graphical primitive for which texturing is enabled. To enable and disable one-dimensional texturing, call $(REF enable) and $(REF disable) with argument `TEXTURE_1D`.
	
	Texture images are defined with $(REF texImage1D). The arguments describe the parameters of the texture image, such as width, width of the border, level-of-detail number (see $(REF texParameter)), and the internal resolution and format used to store the image. The last three arguments describe how the image is represented in memory.
	
	If $(I `target`) is `PROXY_TEXTURE_1D`, no data is read from $(I `data`), but all of the texture image state is recalculated, checked for consistency, and checked against the implementation's capabilities. If the implementation cannot handle a texture of the requested texture size, it sets all of the image state to 0, but does not generate an error (see $(REF getError)). To query for an entire mipmap array, use an image array level greater than or equal to 1.
	
	If $(I `target`) is `TEXTURE_1D`, data is read from $(I `data`) as a sequence of signed or unsigned bytes, shorts, or longs, or single-precision floating-point values, depending on $(I `type`). These values are grouped into sets of one, two, three, or four values, depending on $(I `format`), to form elements. Each data byte is treated as eight 1-bit elements, with bit ordering determined by `UNPACK_LSB_FIRST` (see $(REF pixelStore)).
	
	If a non-zero named buffer object is bound to the `PIXEL_UNPACK_BUFFER` target (see $(REF bindBuffer)) while a texture image is specified, $(I `data`) is treated as a byte offset into the buffer object's data store.
	
	The first element corresponds to the left end of the texture array. Subsequent elements progress left-to-right through the remaining texels in the texture array. The final element corresponds to the right end of the texture array.
	
	$(I `format`) determines the composition of each element in $(I `data`). It can assume one of these symbolic values:
	
	- `RED`: Each element is a single red component. The GL converts it to floating point and assembles it into an RGBA element by attaching 0 for green and blue, and 1 for alpha. Each component is clamped to the range [0,1].
	
	- `RG`: Each element is a single red/green double The GL converts it to floating point and assembles it into an RGBA element by attaching 0 for blue, and 1 for alpha. Each component is clamped to the range [0,1].
	
	- `RGB`,   `BGR`: Each element is an RGB triple. The GL converts it to floating point and assembles it into an RGBA element by attaching 1 for alpha. Each component is clamped to the range [0,1].
	
	- `RGBA`,   `BGRA`: Each element contains all four components. Each component clamped to the range [0,1].
	
	- `DEPTH_COMPONENT`: Each element is a single depth value. The GL converts it to floating point and clamps to the range [0,1].
	
	If an application wants to store the texture at a certain resolution or in a certain format, it can request the resolution and format with $(I `internalformat`). The GL will choose an internal representation that closely approximates that requested by $(I `internalformat`), but it may not match exactly. (The representations specified by `RED`, `RG`, `RGB` and `RGBA` must match exactly.)
	
	$(I `internalformat`) may be one of the base internal formats shown in Table 1, below
	
	$(I `internalformat`) may also be one of the sized internal formats shown in Table 2, below
	
	Finally, $(I `internalformat`) may also be one of the generic or compressed texture formats shown in Table 3 below
	
	If the $(I `internalformat`) parameter is one of the generic compressed formats, `COMPRESSED_RED`, `COMPRESSED_RG`, `COMPRESSED_RGB`, or `COMPRESSED_RGBA`, the GL will replace the internal format with the symbolic constant for a specific internal format and compress the texture before storage. If no corresponding internal format is available, or the GL can not compress that image for any reason, the internal format is instead replaced with a corresponding base internal format.
	
	If the $(I `internalformat`) parameter is `SRGB`, `SRGB8`, `SRGB_ALPHA`or `SRGB8_ALPHA8`, the texture is treated as if the red, green, or blue components are encoded in the sRGB color space. Any alpha component is left unchanged. The conversion from the sRGB encoded component cs to a linear component cl is:
	
	cl={cs12.92ifcs≤0.04045(cs + 0.0551.055)2.4ifcs > 0.04045
	
	Assume cs is the sRGB component in the range [0,1].
	
	Use the `PROXY_TEXTURE_1D` target to try out a resolution and format. The implementation will update and recompute its best match for the requested storage resolution and format. To then query this state, call $(REF getTexLevelParameter). If the texture cannot be accommodated, texture state is set to 0.
	
	A one-component texture image uses only the red component of the RGBA color from $(I `data`). A two-component image uses the R and A values. A three-component image uses the R, G, and B values. A four-component image uses all of the RGBA components.
	
	Image-based shadowing can be enabled by comparing texture r coordinates to depth texture values to generate a boolean result. See $(REF texParameter) for details on texture comparison.
	
	Params:
	target = Specifies the target texture. Must be `TEXTURE_1D` or `PROXY_TEXTURE_1D`.
	level = Specifies the level-of-detail number. Level 0 is the base image level. Level $(I n) is the $(I n)th mipmap reduction image.
	internalformat = Specifies the number of color components in the texture. Must be one of base internal formats given in Table 1, one of the sized internal formats given in Table 2, or one of the compressed internal formats given in Table 3, below.
	width = Specifies the width of the texture image. All implementations support texture images that are at least 1024 texels wide. The height of the 1D texture image is 1.
	border = This value must be 0.
	format = Specifies the format of the pixel data. The following symbolic values are accepted: `RED`, `RG`, `RGB`, `BGR`, `RGBA`, `BGRA`, `RED_INTEGER`, `RG_INTEGER`, `RGB_INTEGER`, `BGR_INTEGER`, `RGBA_INTEGER`, `BGRA_INTEGER`, `STENCIL_INDEX`, `DEPTH_COMPONENT`, `DEPTH_STENCIL`.
	type = Specifies the data type of the pixel data. The following symbolic values are accepted: `UNSIGNED_BYTE`, `BYTE`, `UNSIGNED_SHORT`, `SHORT`, `UNSIGNED_INT`, `INT`, `HALF_FLOAT`, `FLOAT`, `UNSIGNED_BYTE_3_3_2`, `UNSIGNED_BYTE_2_3_3_REV`, `UNSIGNED_SHORT_5_6_5`, `UNSIGNED_SHORT_5_6_5_REV`, `UNSIGNED_SHORT_4_4_4_4`, `UNSIGNED_SHORT_4_4_4_4_REV`, `UNSIGNED_SHORT_5_5_5_1`, `UNSIGNED_SHORT_1_5_5_5_REV`, `UNSIGNED_INT_8_8_8_8`, `UNSIGNED_INT_8_8_8_8_REV`, `UNSIGNED_INT_10_10_10_2`, and `UNSIGNED_INT_2_10_10_10_REV`.
	data = Specifies a pointer to the image data in memory.
	*/
	void texImage1D(Enum target, Int level, Int internalformat, Sizei width, Int border, Enum format, Enum type, const(void)* data);
	
	/**
	Texturing allows elements of an image array to be read by shaders.
	
	To define texture images, call $(REF texImage2D). The arguments describe the parameters of the texture image, such as height, width, width of the border, level-of-detail number (see $(REF texParameter)), and number of color components provided. The last three arguments describe how the image is represented in memory.
	
	If $(I `target`) is `PROXY_TEXTURE_2D`, `PROXY_TEXTURE_1D_ARRAY`, `PROXY_TEXTURE_CUBE_MAP`, or `PROXY_TEXTURE_RECTANGLE`, no data is read from $(I `data`), but all of the texture image state is recalculated, checked for consistency, and checked against the implementation's capabilities. If the implementation cannot handle a texture of the requested texture size, it sets all of the image state to 0, but does not generate an error (see $(REF getError)). To query for an entire mipmap array, use an image array level greater than or equal to 1.
	
	If $(I `target`) is `TEXTURE_2D`, `TEXTURE_RECTANGLE` or one of the `TEXTURE_CUBE_MAP` targets, data is read from $(I `data`) as a sequence of signed or unsigned bytes, shorts, or longs, or single-precision floating-point values, depending on $(I `type`). These values are grouped into sets of one, two, three, or four values, depending on $(I `format`), to form elements. Each data byte is treated as eight 1-bit elements, with bit ordering determined by `UNPACK_LSB_FIRST` (see $(REF pixelStore)).
	
	If $(I `target`) is `TEXTURE_1D_ARRAY`, data is interpreted as an array of one-dimensional images.
	
	If a non-zero named buffer object is bound to the `PIXEL_UNPACK_BUFFER` target (see $(REF bindBuffer)) while a texture image is specified, $(I `data`) is treated as a byte offset into the buffer object's data store.
	
	The first element corresponds to the lower left corner of the texture image. Subsequent elements progress left-to-right through the remaining texels in the lowest row of the texture image, and then in successively higher rows of the texture image. The final element corresponds to the upper right corner of the texture image.
	
	$(I `format`) determines the composition of each element in $(I `data`). It can assume one of these symbolic values:
	
	- `RED`: Each element is a single red component. The GL converts it to floating point and assembles it into an RGBA element by attaching 0 for green and blue, and 1 for alpha. Each component is clamped to the range [0,1].
	
	- `RG`: Each element is a red/green double. The GL converts it to floating point and assembles it into an RGBA element by attaching 0 for blue, and 1 for alpha. Each component is clamped to the range [0,1].
	
	- `RGB`,   `BGR`: Each element is an RGB triple. The GL converts it to floating point and assembles it into an RGBA element by attaching 1 for alpha. Each component is clamped to the range [0,1].
	
	- `RGBA`,   `BGRA`: Each element contains all four components. Each component is clamped to the range [0,1].
	
	- `DEPTH_COMPONENT`: Each element is a single depth value. The GL converts it to floating point and clamps to the range [0,1].
	
	- `DEPTH_STENCIL`: Each element is a pair of depth and stencil values. The depth component of the pair is interpreted as in `DEPTH_COMPONENT`. The stencil component is interpreted based on specified the depth + stencil internal format.
	
	If an application wants to store the texture at a certain resolution or in a certain format, it can request the resolution and format with $(I `internalformat`). The GL will choose an internal representation that closely approximates that requested by $(I `internalformat`), but it may not match exactly. (The representations specified by `RED`, `RG`, `RGB`, and `RGBA` must match exactly.)
	
	$(I `internalformat`) may be one of the base internal formats shown in Table 1, below
	
	$(I `internalformat`) may also be one of the sized internal formats shown in Table 2, below
	
	Finally, $(I `internalformat`) may also be one of the generic or compressed texture formats shown in Table 3 below
	
	If the $(I `internalformat`) parameter is one of the generic compressed formats, `COMPRESSED_RED`, `COMPRESSED_RG`, `COMPRESSED_RGB`, or `COMPRESSED_RGBA`, the GL will replace the internal format with the symbolic constant for a specific internal format and compress the texture before storage. If no corresponding internal format is available, or the GL can not compress that image for any reason, the internal format is instead replaced with a corresponding base internal format.
	
	If the $(I `internalformat`) parameter is `SRGB`, `SRGB8`, `SRGB_ALPHA`, or `SRGB8_ALPHA8`, the texture is treated as if the red, green, or blue components are encoded in the sRGB color space. Any alpha component is left unchanged. The conversion from the sRGB encoded component cs to a linear component cl is:
	
	cl={cs12.92ifcs≤0.04045(cs + 0.0551.055)2.4ifcs > 0.04045
	
	Assume cs is the sRGB component in the range [0,1].
	
	Use the `PROXY_TEXTURE_2D`, `PROXY_TEXTURE_1D_ARRAY`, `PROXY_TEXTURE_RECTANGLE`, or `PROXY_TEXTURE_CUBE_MAP` target to try out a resolution and format. The implementation will update and recompute its best match for the requested storage resolution and format. To then query this state, call $(REF getTexLevelParameter). If the texture cannot be accommodated, texture state is set to 0.
	
	A one-component texture image uses only the red component of the RGBA color extracted from $(I `data`). A two-component image uses the R and G values. A three-component image uses the R, G, and B values. A four-component image uses all of the RGBA components.
	
	Image-based shadowing can be enabled by comparing texture r coordinates to depth texture values to generate a boolean result. See $(REF texParameter) for details on texture comparison.
	
	Params:
	target = Specifies the target texture. Must be `TEXTURE_2D`, `PROXY_TEXTURE_2D`, `TEXTURE_1D_ARRAY`, `PROXY_TEXTURE_1D_ARRAY`, `TEXTURE_RECTANGLE`, `PROXY_TEXTURE_RECTANGLE`, `TEXTURE_CUBE_MAP_POSITIVE_X`, `TEXTURE_CUBE_MAP_NEGATIVE_X`, `TEXTURE_CUBE_MAP_POSITIVE_Y`, `TEXTURE_CUBE_MAP_NEGATIVE_Y`, `TEXTURE_CUBE_MAP_POSITIVE_Z`, `TEXTURE_CUBE_MAP_NEGATIVE_Z`, or `PROXY_TEXTURE_CUBE_MAP`.
	level = Specifies the level-of-detail number. Level 0 is the base image level. Level $(I n) is the $(I n)th mipmap reduction image. If $(I `target`) is `TEXTURE_RECTANGLE` or `PROXY_TEXTURE_RECTANGLE`, $(I `level`) must be 0.
	internalformat = Specifies the number of color components in the texture. Must be one of base internal formats given in Table 1, one of the sized internal formats given in Table 2, or one of the compressed internal formats given in Table 3, below.
	width = Specifies the width of the texture image. All implementations support texture images that are at least 1024 texels wide.
	height = Specifies the height of the texture image, or the number of layers in a texture array, in the case of the `TEXTURE_1D_ARRAY` and `PROXY_TEXTURE_1D_ARRAY` targets. All implementations support 2D texture images that are at least 1024 texels high, and texture arrays that are at least 256 layers deep.
	border = This value must be 0.
	format = Specifies the format of the pixel data. The following symbolic values are accepted: `RED`, `RG`, `RGB`, `BGR`, `RGBA`, `BGRA`, `RED_INTEGER`, `RG_INTEGER`, `RGB_INTEGER`, `BGR_INTEGER`, `RGBA_INTEGER`, `BGRA_INTEGER`, `STENCIL_INDEX`, `DEPTH_COMPONENT`, `DEPTH_STENCIL`.
	type = Specifies the data type of the pixel data. The following symbolic values are accepted: `UNSIGNED_BYTE`, `BYTE`, `UNSIGNED_SHORT`, `SHORT`, `UNSIGNED_INT`, `INT`, `HALF_FLOAT`, `FLOAT`, `UNSIGNED_BYTE_3_3_2`, `UNSIGNED_BYTE_2_3_3_REV`, `UNSIGNED_SHORT_5_6_5`, `UNSIGNED_SHORT_5_6_5_REV`, `UNSIGNED_SHORT_4_4_4_4`, `UNSIGNED_SHORT_4_4_4_4_REV`, `UNSIGNED_SHORT_5_5_5_1`, `UNSIGNED_SHORT_1_5_5_5_REV`, `UNSIGNED_INT_8_8_8_8`, `UNSIGNED_INT_8_8_8_8_REV`, `UNSIGNED_INT_10_10_10_2`, and `UNSIGNED_INT_2_10_10_10_REV`.
	data = Specifies a pointer to the image data in memory.
	*/
	void texImage2D(Enum target, Int level, Int internalformat, Sizei width, Sizei height, Int border, Enum format, Enum type, const(void)* data);
	
	/**
	When colors are written to the frame buffer, they are written into the color buffers specified by $(REF drawBuffer). One of the following values can be used for default framebuffer:
	
	- `NONE`: No color buffers are written.
	
	- `FRONT_LEFT`: Only the front left color buffer is written.
	
	- `FRONT_RIGHT`: Only the front right color buffer is written.
	
	- `BACK_LEFT`: Only the back left color buffer is written.
	
	- `BACK_RIGHT`: Only the back right color buffer is written.
	
	- `FRONT`: Only the front left and front right color buffers are written. If there is no front right color buffer, only the front left color buffer is written.
	
	- `BACK`: Only the back left and back right color buffers are written. If there is no back right color buffer, only the back left color buffer is written.
	
	- `LEFT`: Only the front left and back left color buffers are written. If there is no back left color buffer, only the front left color buffer is written.
	
	- `RIGHT`: Only the front right and back right color buffers are written. If there is no back right color buffer, only the front right color buffer is written.
	
	- `FRONT_AND_BACK`: All the front and back color buffers (front left, front right, back left, back right) are written. If there are no back color buffers, only the front left and front right color buffers are written. If there are no right color buffers, only the front left and back left color buffers are written. If there are no right or back color buffers, only the front left color buffer is written.
	
	If more than one color buffer is selected for drawing, then blending or logical operations are computed and applied independently for each color buffer and can produce different results in each buffer.
	
	Monoscopic contexts include only $(I left) buffers, and stereoscopic contexts include both $(I left) and $(I right) buffers. Likewise, single-buffered contexts include only $(I front) buffers, and double-buffered contexts include both $(I front) and $(I back) buffers. The context is selected at GL initialization.
	
	For framebuffer objects, `COLOR_ATTACHMENT$m$` and `NONE` enums are accepted, where `$m$` is a value between 0 and `MAX_COLOR_ATTACHMENTS`. glDrawBuffer will set the draw buffer for fragment colors other than zero to `NONE`.
	
	Params:
	buf = For default framebuffer, the argument specifies up to four color buffers to be drawn into. Symbolic constants `NONE`, `FRONT_LEFT`, `FRONT_RIGHT`, `BACK_LEFT`, `BACK_RIGHT`, `FRONT`, `BACK`, `LEFT`, `RIGHT`, and `FRONT_AND_BACK` are accepted. The initial value is `FRONT` for single-buffered contexts, and `BACK` for double-buffered contexts. For framebuffer objects, `COLOR_ATTACHMENT$m$` and `NONE` enums are accepted, where `$m$` is a value between 0 and `MAX_COLOR_ATTACHMENTS`.
	*/
	void drawBuffer(Enum buf);
	
	/**
	$(REF clear) sets the bitplane area of the window to values previously selected by $(REF clearColor), $(REF clearDepth), and $(REF clearStencil). Multiple color buffers can be cleared simultaneously by selecting more than one buffer at a time using $(REF drawBuffer).
	
	The pixel ownership test, the scissor test, dithering, and the buffer writemasks affect the operation of $(REF clear). The scissor box bounds the cleared region. Alpha function, blend function, logical operation, stenciling, texture mapping, and depth-buffering are ignored by $(REF clear).
	
	$(REF clear) takes a single argument that is the bitwise OR of several values indicating which buffer is to be cleared.
	
	The values are as follows:
	
	- `COLOR_BUFFER_BIT`: Indicates the buffers currently enabled for color writing.
	
	- `DEPTH_BUFFER_BIT`: Indicates the depth buffer.
	
	- `STENCIL_BUFFER_BIT`: Indicates the stencil buffer.
	
	The value to which each buffer is cleared depends on the setting of the clear value for that buffer.
	
	Params:
	mask = Bitwise OR of masks that indicate the buffers to be cleared. The three masks are `COLOR_BUFFER_BIT`, `DEPTH_BUFFER_BIT`, and `STENCIL_BUFFER_BIT`.
	*/
	void clear(Bitfield mask);
	
	/**
	$(REF clearColor) specifies the red, green, blue, and alpha values used by $(REF clear) to clear the color buffers. Values specified by $(REF clearColor) are clamped to the range [0, 1].
	
	Params:
	red = Specify the red, green, blue, and alpha values used when the color buffers are cleared. The initial values are all 0.
	green = Specify the red, green, blue, and alpha values used when the color buffers are cleared. The initial values are all 0.
	blue = Specify the red, green, blue, and alpha values used when the color buffers are cleared. The initial values are all 0.
	alpha = Specify the red, green, blue, and alpha values used when the color buffers are cleared. The initial values are all 0.
	*/
	void clearColor(Float red, Float green, Float blue, Float alpha);
	
	/**
	$(REF clearStencil) specifies the index used by $(REF clear) to clear the stencil buffer. $(I `s`) is masked with 2m - 1, where m is the number of bits in the stencil buffer.
	
	Params:
	s = Specifies the index used when the stencil buffer is cleared. The initial value is 0.
	*/
	void clearStencil(Int s);
	
	/**
	$(REF clearDepth) specifies the depth value used by $(REF clear) to clear the depth buffer. Values specified by $(REF clearDepth) are clamped to the range [0, 1].
	
	Params:
	depth = Specifies the depth value used when the depth buffer is cleared. The initial value is 1.
	*/
	void clearDepth(Double depth);
	
	/**
	$(REF stencilMask) controls the writing of individual bits in the stencil planes. The least significant n bits of $(I `mask`), where n is the number of bits in the stencil buffer, specify a mask. Where a 1 appears in the mask, it's possible to write to the corresponding bit in the stencil buffer. Where a 0 appears, the corresponding bit is write-protected. Initially, all bits are enabled for writing.
	
	There can be two separate $(I `mask`) writemasks; one affects back-facing polygons, and the other affects front-facing polygons as well as other non-polygon primitives. $(REF stencilMask) sets both front and back stencil writemasks to the same values. Use $(REF stencilMaskSeparate) to set front and back stencil writemasks to different values.
	
	Params:
	mask = Specifies a bit mask to enable and disable writing of individual bits in the stencil planes. Initially, the mask is all 1's.
	*/
	void stencilMask(UInt mask);
	
	/**
	$(REF colorMask) and $(REF colorMaski) specify whether the individual color components in the frame buffer can or cannot be written. $(REF colorMaski) sets the mask for a specific draw buffer, whereas $(REF colorMask) sets the mask for all draw buffers. If $(I `red`) is `FALSE`, for example, no change is made to the red component of any pixel in any of the color buffers, regardless of the drawing operation attempted.
	
	Changes to individual bits of components cannot be controlled. Rather, changes are either enabled or disabled for entire color components.
	
	Params:
	red = Specify whether red, green, blue, and alpha are to be written into the frame buffer. The initial values are all `TRUE`, indicating that the color components are written.
	green = Specify whether red, green, blue, and alpha are to be written into the frame buffer. The initial values are all `TRUE`, indicating that the color components are written.
	blue = Specify whether red, green, blue, and alpha are to be written into the frame buffer. The initial values are all `TRUE`, indicating that the color components are written.
	alpha = Specify whether red, green, blue, and alpha are to be written into the frame buffer. The initial values are all `TRUE`, indicating that the color components are written.
	*/
	void colorMask(Boolean red, Boolean green, Boolean blue, Boolean alpha);
	
	/**
	$(REF depthMask) specifies whether the depth buffer is enabled for writing. If $(I `flag`) is `FALSE`, depth buffer writing is disabled. Otherwise, it is enabled. Initially, depth buffer writing is enabled.
	
	Params:
	flag = Specifies whether the depth buffer is enabled for writing. If $(I `flag`) is `FALSE`, depth buffer writing is disabled. Otherwise, it is enabled. Initially, depth buffer writing is enabled.
	*/
	void depthMask(Boolean flag);
	
	/**
	$(REF enable) and $(REF disable) enable and disable various capabilities. Use $(REF isEnabled) or $(REF get) to determine the current setting of any capability. The initial value for each capability with the exception of `DITHER` and `MULTISAMPLE` is `FALSE`. The initial value for `DITHER` and `MULTISAMPLE` is `TRUE`.
	
	Both $(REF enable) and $(REF disable) take a single argument, $(I `cap`), which can assume one of the following values:
	
	Some of the GL's capabilities are indexed. $(REF enablei) and $(REF disablei) enable and disable indexed capabilities.
	
	- `BLEND`: If enabled, blend the computed fragment color values with the values in the color buffers. See $(REF blendFunc).
	
	- `CLIP_DISTANCE`  $(I i): If enabled, clip geometry against user-defined half space $(I i).
	
	- `COLOR_LOGIC_OP`: If enabled, apply the currently selected logical operation to the computed fragment color and color buffer values. See $(REF logicOp).
	
	- `CULL_FACE`: If enabled, cull polygons based on their winding in window coordinates. See $(REF cullFace).
	
	- `DEBUG_OUTPUT`: If enabled, debug messages are produced by a debug context. When disabled, the debug message log is silenced. Note that in a non-debug context, very few, if any messages might be produced, even when `DEBUG_OUTPUT` is enabled.
	
	- `DEBUG_OUTPUT_SYNCHRONOUS`: If enabled, debug messages are produced synchronously by a debug context. If disabled, debug messages may be produced asynchronously. In particular, they may be delayed relative to the execution of GL commands, and the debug callback function may be called from a thread other than that in which the commands are executed. See $(REF debugMessageCallback).
	
	- `DEPTH_CLAMP`: If enabled, the  -wc≤zc≤wc  plane equation is ignored by view volume clipping (effectively, there is no near or far plane clipping). See $(REF depthRange).
	
	- `DEPTH_TEST`: If enabled, do depth comparisons and update the depth buffer. Note that even if the depth buffer exists and the depth mask is non-zero, the depth buffer is not updated if the depth test is disabled. See $(REF depthFunc) and $(REF depthRange).
	
	- `DITHER`: If enabled, dither color components or indices before they are written to the color buffer.
	
	- `FRAMEBUFFER_SRGB`: If enabled and the value of `FRAMEBUFFER_ATTACHMENT_COLOR_ENCODING` for the framebuffer attachment corresponding to the destination buffer is `SRGB`, the R, G, and B destination color values (after conversion from fixed-point to floating-point) are considered to be encoded for the sRGB color space and hence are linearized prior to their use in blending.
	
	- `LINE_SMOOTH`: If enabled, draw lines with correct filtering. Otherwise, draw aliased lines. See $(REF lineWidth).
	
	- `MULTISAMPLE`: If enabled, use multiple fragment samples in computing the final color of a pixel. See $(REF sampleCoverage).
	
	- `POLYGON_OFFSET_FILL`: If enabled, and if the polygon is rendered in `FILL` mode, an offset is added to depth values of a polygon's fragments before the depth comparison is performed. See $(REF polygonOffset).
	
	- `POLYGON_OFFSET_LINE`: If enabled, and if the polygon is rendered in `LINE` mode, an offset is added to depth values of a polygon's fragments before the depth comparison is performed. See $(REF polygonOffset).
	
	- `POLYGON_OFFSET_POINT`: If enabled, an offset is added to depth values of a polygon's fragments before the depth comparison is performed, if the polygon is rendered in `POINT` mode. See $(REF polygonOffset).
	
	- `POLYGON_SMOOTH`: If enabled, draw polygons with proper filtering. Otherwise, draw aliased polygons. For correct antialiased polygons, an alpha buffer is needed and the polygons must be sorted front to back.
	
	- `PRIMITIVE_RESTART`: Enables primitive restarting. If enabled, any one of the draw commands which transfers a set of generic attribute array elements to the GL will restart the primitive when the index of the vertex is equal to the primitive restart index. See $(REF primitiveRestartIndex).
	
	- `PRIMITIVE_RESTART_FIXED_INDEX`: Enables primitive restarting with a fixed index. If enabled, any one of the draw commands which transfers a set of generic attribute array elements to the GL will restart the primitive when the index of the vertex is equal to the fixed primitive index for the specified index type. The fixed index is equal to 2n−1 where $(I n) is equal to 8 for `UNSIGNED_BYTE`, 16 for `UNSIGNED_SHORT` and 32 for `UNSIGNED_INT`.
	
	- `RASTERIZER_DISCARD`: If enabled, primitives are discarded after the optional transform feedback stage, but before rasterization. Furthermore, when enabled, $(REF clear), $(REF clearBufferData), $(REF clearBufferSubData), $(REF clearTexImage), and $(REF clearTexSubImage) are ignored.
	
	- `SAMPLE_ALPHA_TO_COVERAGE`: If enabled, compute a temporary coverage value where each bit is determined by the alpha value at the corresponding sample location. The temporary coverage value is then ANDed with the fragment coverage value.
	
	- `SAMPLE_ALPHA_TO_ONE`: If enabled, each sample alpha value is replaced by the maximum representable alpha value.
	
	- `SAMPLE_COVERAGE`: If enabled, the fragment's coverage is ANDed with the temporary coverage value. If `SAMPLE_COVERAGE_INVERT` is set to `TRUE`, invert the coverage value. See $(REF sampleCoverage).
	
	- `SAMPLE_SHADING`: If enabled, the active fragment shader is run once for each covered sample, or at fraction of this rate as determined by the current value of `MIN_SAMPLE_SHADING_VALUE`. See $(REF minSampleShading).
	
	- `SAMPLE_MASK`: If enabled, the sample coverage mask generated for a fragment during rasterization will be ANDed with the value of `SAMPLE_MASK_VALUE` before shading occurs. See $(REF sampleMaski).
	
	- `SCISSOR_TEST`: If enabled, discard fragments that are outside the scissor rectangle. See $(REF scissor).
	
	- `STENCIL_TEST`: If enabled, do stencil testing and update the stencil buffer. See $(REF stencilFunc) and $(REF stencilOp).
	
	- `TEXTURE_CUBE_MAP_SEAMLESS`: If enabled, cubemap textures are sampled such that when linearly sampling from the border between two adjacent faces, texels from both faces are used to generate the final sample value. When disabled, texels from only a single face are used to construct the final sample value.
	
	- `PROGRAM_POINT_SIZE`: If enabled and a vertex or geometry shader is active, then the derived point size is taken from the (potentially clipped) shader builtin `gl_PointSize` and clamped to the implementation-dependent point size range.
	
	Params:
	cap = Specifies a symbolic constant indicating a GL capability.
	*/
	void disable(Enum cap);
	
	/**
	$(REF enable) and $(REF disable) enable and disable various capabilities. Use $(REF isEnabled) or $(REF get) to determine the current setting of any capability. The initial value for each capability with the exception of `DITHER` and `MULTISAMPLE` is `FALSE`. The initial value for `DITHER` and `MULTISAMPLE` is `TRUE`.
	
	Both $(REF enable) and $(REF disable) take a single argument, $(I `cap`), which can assume one of the following values:
	
	Some of the GL's capabilities are indexed. $(REF enablei) and $(REF disablei) enable and disable indexed capabilities.
	
	- `BLEND`: If enabled, blend the computed fragment color values with the values in the color buffers. See $(REF blendFunc).
	
	- `CLIP_DISTANCE`  $(I i): If enabled, clip geometry against user-defined half space $(I i).
	
	- `COLOR_LOGIC_OP`: If enabled, apply the currently selected logical operation to the computed fragment color and color buffer values. See $(REF logicOp).
	
	- `CULL_FACE`: If enabled, cull polygons based on their winding in window coordinates. See $(REF cullFace).
	
	- `DEBUG_OUTPUT`: If enabled, debug messages are produced by a debug context. When disabled, the debug message log is silenced. Note that in a non-debug context, very few, if any messages might be produced, even when `DEBUG_OUTPUT` is enabled.
	
	- `DEBUG_OUTPUT_SYNCHRONOUS`: If enabled, debug messages are produced synchronously by a debug context. If disabled, debug messages may be produced asynchronously. In particular, they may be delayed relative to the execution of GL commands, and the debug callback function may be called from a thread other than that in which the commands are executed. See $(REF debugMessageCallback).
	
	- `DEPTH_CLAMP`: If enabled, the  -wc≤zc≤wc  plane equation is ignored by view volume clipping (effectively, there is no near or far plane clipping). See $(REF depthRange).
	
	- `DEPTH_TEST`: If enabled, do depth comparisons and update the depth buffer. Note that even if the depth buffer exists and the depth mask is non-zero, the depth buffer is not updated if the depth test is disabled. See $(REF depthFunc) and $(REF depthRange).
	
	- `DITHER`: If enabled, dither color components or indices before they are written to the color buffer.
	
	- `FRAMEBUFFER_SRGB`: If enabled and the value of `FRAMEBUFFER_ATTACHMENT_COLOR_ENCODING` for the framebuffer attachment corresponding to the destination buffer is `SRGB`, the R, G, and B destination color values (after conversion from fixed-point to floating-point) are considered to be encoded for the sRGB color space and hence are linearized prior to their use in blending.
	
	- `LINE_SMOOTH`: If enabled, draw lines with correct filtering. Otherwise, draw aliased lines. See $(REF lineWidth).
	
	- `MULTISAMPLE`: If enabled, use multiple fragment samples in computing the final color of a pixel. See $(REF sampleCoverage).
	
	- `POLYGON_OFFSET_FILL`: If enabled, and if the polygon is rendered in `FILL` mode, an offset is added to depth values of a polygon's fragments before the depth comparison is performed. See $(REF polygonOffset).
	
	- `POLYGON_OFFSET_LINE`: If enabled, and if the polygon is rendered in `LINE` mode, an offset is added to depth values of a polygon's fragments before the depth comparison is performed. See $(REF polygonOffset).
	
	- `POLYGON_OFFSET_POINT`: If enabled, an offset is added to depth values of a polygon's fragments before the depth comparison is performed, if the polygon is rendered in `POINT` mode. See $(REF polygonOffset).
	
	- `POLYGON_SMOOTH`: If enabled, draw polygons with proper filtering. Otherwise, draw aliased polygons. For correct antialiased polygons, an alpha buffer is needed and the polygons must be sorted front to back.
	
	- `PRIMITIVE_RESTART`: Enables primitive restarting. If enabled, any one of the draw commands which transfers a set of generic attribute array elements to the GL will restart the primitive when the index of the vertex is equal to the primitive restart index. See $(REF primitiveRestartIndex).
	
	- `PRIMITIVE_RESTART_FIXED_INDEX`: Enables primitive restarting with a fixed index. If enabled, any one of the draw commands which transfers a set of generic attribute array elements to the GL will restart the primitive when the index of the vertex is equal to the fixed primitive index for the specified index type. The fixed index is equal to 2n−1 where $(I n) is equal to 8 for `UNSIGNED_BYTE`, 16 for `UNSIGNED_SHORT` and 32 for `UNSIGNED_INT`.
	
	- `RASTERIZER_DISCARD`: If enabled, primitives are discarded after the optional transform feedback stage, but before rasterization. Furthermore, when enabled, $(REF clear), $(REF clearBufferData), $(REF clearBufferSubData), $(REF clearTexImage), and $(REF clearTexSubImage) are ignored.
	
	- `SAMPLE_ALPHA_TO_COVERAGE`: If enabled, compute a temporary coverage value where each bit is determined by the alpha value at the corresponding sample location. The temporary coverage value is then ANDed with the fragment coverage value.
	
	- `SAMPLE_ALPHA_TO_ONE`: If enabled, each sample alpha value is replaced by the maximum representable alpha value.
	
	- `SAMPLE_COVERAGE`: If enabled, the fragment's coverage is ANDed with the temporary coverage value. If `SAMPLE_COVERAGE_INVERT` is set to `TRUE`, invert the coverage value. See $(REF sampleCoverage).
	
	- `SAMPLE_SHADING`: If enabled, the active fragment shader is run once for each covered sample, or at fraction of this rate as determined by the current value of `MIN_SAMPLE_SHADING_VALUE`. See $(REF minSampleShading).
	
	- `SAMPLE_MASK`: If enabled, the sample coverage mask generated for a fragment during rasterization will be ANDed with the value of `SAMPLE_MASK_VALUE` before shading occurs. See $(REF sampleMaski).
	
	- `SCISSOR_TEST`: If enabled, discard fragments that are outside the scissor rectangle. See $(REF scissor).
	
	- `STENCIL_TEST`: If enabled, do stencil testing and update the stencil buffer. See $(REF stencilFunc) and $(REF stencilOp).
	
	- `TEXTURE_CUBE_MAP_SEAMLESS`: If enabled, cubemap textures are sampled such that when linearly sampling from the border between two adjacent faces, texels from both faces are used to generate the final sample value. When disabled, texels from only a single face are used to construct the final sample value.
	
	- `PROGRAM_POINT_SIZE`: If enabled and a vertex or geometry shader is active, then the derived point size is taken from the (potentially clipped) shader builtin `gl_PointSize` and clamped to the implementation-dependent point size range.
	
	Params:
	cap = Specifies a symbolic constant indicating a GL capability.
	*/
	void enable(Enum cap);
	
	/**
	$(REF finish) does not return until the effects of all previously called GL commands are complete. Such effects include all changes to GL state, all changes to connection state, and all changes to the frame buffer contents.
	
	Params:
	*/
	void finish();
	
	/**
	Different GL implementations buffer commands in several different locations, including network buffers and the graphics accelerator itself. $(REF flush) empties all of these buffers, causing all issued commands to be executed as quickly as they are accepted by the actual rendering engine. Though this execution may not be completed in any particular time period, it does complete in finite time.
	
	Because any GL program might be executed over a network, or on an accelerator that buffers commands, all programs should call $(REF flush) whenever they count on having all of their previously issued commands completed. For example, call $(REF flush) before waiting for user input that depends on the generated image.
	
	Params:
	*/
	void flush();
	
	/**
	Pixels can be drawn using a function that blends the incoming (source) RGBA values with the RGBA values that are already in the frame buffer (the destination values). Blending is initially disabled. Use $(REF enable) and $(REF disable) with argument `BLEND` to enable and disable blending.
	
	$(REF blendFunc) defines the operation of blending for all draw buffers when it is enabled. $(REF blendFunci) defines the operation of blending for a single draw buffer specified by $(I `buf`) when enabled for that draw buffer. $(I `sfactor`) specifies which method is used to scale the source color components. $(I `dfactor`) specifies which method is used to scale the destination color components. Both parameters must be one of the following symbolic constants: `ZERO`, `ONE`, `SRC_COLOR`, `ONE_MINUS_SRC_COLOR`, `DST_COLOR`, `ONE_MINUS_DST_COLOR`, `SRC_ALPHA`, `ONE_MINUS_SRC_ALPHA`, `DST_ALPHA`, `ONE_MINUS_DST_ALPHA`, `CONSTANT_COLOR`, `ONE_MINUS_CONSTANT_COLOR`, `CONSTANT_ALPHA`, `ONE_MINUS_CONSTANT_ALPHA`, `SRC_ALPHA_SATURATE`, `SRC1_COLOR`, `ONE_MINUS_SRC1_COLOR`, `SRC1_ALPHA`, and `ONE_MINUS_SRC1_ALPHA`. The possible methods are described in the following table. Each method defines four scale factors, one each for red, green, blue, and alpha. In the table and in subsequent equations, first source, second source and destination color components are referred to as (Rs0, Gs0, Bs0, As0), (Rs1, Gs1, Bs1, As1) and (Rd, Gd, Bd, Ad), respectively. The color specified by $(REF blendColor) is referred to as (Rc, Gc, Bc, Ac). They are understood to have integer values between 0 and (kR, kG, kB, kA), where
	
	kc=2mc - 1
	
	and (mR, mG, mB, mA) is the number of red, green, blue, and alpha bitplanes.
	
	Source and destination scale factors are referred to as (sR, sG, sB, sA) and (dR, dG, dB, dA). The scale factors described in the table, denoted (fR, fG, fB, fA), represent either source or destination factors. All scale factors have range [0, 1].
	
	In the table,
	
	i=min⁡(As, kA - Ad)kA
	
	To determine the blended RGBA values of a pixel, the system uses the following equations:
	
	Rd=min⁡(kR, Rs⁢sR + Rd⁢dR) Gd=min⁡(kG, Gs⁢sG + Gd⁢dG) Bd=min⁡(kB, Bs⁢sB + Bd⁢dB) Ad=min⁡(kA, As⁢sA + Ad⁢dA)
	
	Despite the apparent precision of the above equations, blending arithmetic is not exactly specified, because blending operates with imprecise integer color values. However, a blend factor that should be equal to 1 is guaranteed not to modify its multiplicand, and a blend factor equal to 0 reduces its multiplicand to 0. For example, when $(I `sfactor`) is `SRC_ALPHA`, $(I `dfactor`) is `ONE_MINUS_SRC_ALPHA`, and As is equal to kA, the equations reduce to simple replacement:
	
	Rd=Rs Gd=Gs Bd=Bs Ad=As
	
	Params:
	sfactor = Specifies how the red, green, blue, and alpha source blending factors are computed. The initial value is `ONE`.
	dfactor = Specifies how the red, green, blue, and alpha destination blending factors are computed. The following symbolic constants are accepted: `ZERO`, `ONE`, `SRC_COLOR`, `ONE_MINUS_SRC_COLOR`, `DST_COLOR`, `ONE_MINUS_DST_COLOR`, `SRC_ALPHA`, `ONE_MINUS_SRC_ALPHA`, `DST_ALPHA`, `ONE_MINUS_DST_ALPHA`. `CONSTANT_COLOR`, `ONE_MINUS_CONSTANT_COLOR`, `CONSTANT_ALPHA`, and `ONE_MINUS_CONSTANT_ALPHA`. The initial value is `ZERO`.
	*/
	void blendFunc(Enum sfactor, Enum dfactor);
	
	/**
	$(REF logicOp) specifies a logical operation that, when enabled, is applied between the incoming RGBA color and the RGBA color at the corresponding location in the frame buffer. To enable or disable the logical operation, call $(REF enable) and $(REF disable) using the symbolic constant `COLOR_LOGIC_OP`. The initial value is disabled.
	
	$(I `opcode`) is a symbolic constant chosen from the list above. In the explanation of the logical operations, $(I s) represents the incoming color and $(I d) represents the color in the frame buffer. Standard C-language operators are used. As these bitwise operators suggest, the logical operation is applied independently to each bit pair of the source and destination colors.
	
	Params:
	opcode = Specifies a symbolic constant that selects a logical operation. The following symbols are accepted: `CLEAR`, `SET`, `COPY`, `COPY_INVERTED`, `NOOP`, `INVERT`, `AND`, `NAND`, `OR`, `NOR`, `XOR`, `EQUIV`, `AND_REVERSE`, `AND_INVERTED`, `OR_REVERSE`, and `OR_INVERTED`. The initial value is `COPY`.
	*/
	void logicOp(Enum opcode);
	
	/**
	Stenciling, like depth-buffering, enables and disables drawing on a per-pixel basis. Stencil planes are first drawn into using GL drawing primitives, then geometry and images are rendered using the stencil planes to mask out portions of the screen. Stenciling is typically used in multipass rendering algorithms to achieve special effects, such as decals, outlining, and constructive solid geometry rendering.
	
	The stencil test conditionally eliminates a pixel based on the outcome of a comparison between the reference value and the value in the stencil buffer. To enable and disable the test, call $(REF enable) and $(REF disable) with argument `STENCIL_TEST`. To specify actions based on the outcome of the stencil test, call $(REF stencilOp) or $(REF stencilOpSeparate).
	
	There can be two separate sets of $(I `func`), $(I `ref`), and $(I `mask`) parameters; one affects back-facing polygons, and the other affects front-facing polygons as well as other non-polygon primitives. $(REF stencilFunc) sets both front and back stencil state to the same values. Use $(REF stencilFuncSeparate) to set front and back stencil state to different values.
	
	$(I `func`) is a symbolic constant that determines the stencil comparison function. It accepts one of eight values, shown in the following list. $(I `ref`) is an integer reference value that is used in the stencil comparison. It is clamped to the range [0, 2n - 1], where n is the number of bitplanes in the stencil buffer. $(I `mask`) is bitwise ANDed with both the reference value and the stored stencil value, with the ANDed values participating in the comparison.
	
	If $(I stencil) represents the value stored in the corresponding stencil buffer location, the following list shows the effect of each comparison function that can be specified by $(I `func`). Only if the comparison succeeds is the pixel passed through to the next stage in the rasterization process (see $(REF stencilOp)). All tests treat $(I stencil) values as unsigned integers in the range [0, 2n - 1], where n is the number of bitplanes in the stencil buffer.
	
	The following values are accepted by $(I `func`):
	
	- `NEVER`: Always fails.
	
	- `LESS`: Passes if ( $(I `ref`) & $(I `mask`) ) < ( $(I stencil) & $(I `mask`) ).
	
	- `LEQUAL`: Passes if ( $(I `ref`) & $(I `mask`) ) <= ( $(I stencil) & $(I `mask`) ).
	
	- `GREATER`: Passes if ( $(I `ref`) & $(I `mask`) ) > ( $(I stencil) & $(I `mask`) ).
	
	- `GEQUAL`: Passes if ( $(I `ref`) & $(I `mask`) ) >= ( $(I stencil) & $(I `mask`) ).
	
	- `EQUAL`: Passes if ( $(I `ref`) & $(I `mask`) ) = ( $(I stencil) & $(I `mask`) ).
	
	- `NOTEQUAL`: Passes if ( $(I `ref`) & $(I `mask`) ) != ( $(I stencil) & $(I `mask`) ).
	
	- `ALWAYS`: Always passes.
	
	Params:
	func = Specifies the test function. Eight symbolic constants are valid: `NEVER`, `LESS`, `LEQUAL`, `GREATER`, `GEQUAL`, `EQUAL`, `NOTEQUAL`, and `ALWAYS`. The initial value is `ALWAYS`.
	ref = Specifies the reference value for the stencil test. $(I `ref`) is clamped to the range   0  2 n  - 1   , where n is the number of bitplanes in the stencil buffer. The initial value is 0.
	mask = Specifies a mask that is ANDed with both the reference value and the stored stencil value when the test is done. The initial value is all 1's.
	*/
	void stencilFunc(Enum func, Int ref_, UInt mask);
	
	/**
	Stenciling, like depth-buffering, enables and disables drawing on a per-pixel basis. You draw into the stencil planes using GL drawing primitives, then render geometry and images, using the stencil planes to mask out portions of the screen. Stenciling is typically used in multipass rendering algorithms to achieve special effects, such as decals, outlining, and constructive solid geometry rendering.
	
	The stencil test conditionally eliminates a pixel based on the outcome of a comparison between the value in the stencil buffer and a reference value. To enable and disable the test, call $(REF enable) and $(REF disable) with argument `STENCIL_TEST`; to control it, call $(REF stencilFunc) or $(REF stencilFuncSeparate).
	
	There can be two separate sets of $(I `sfail`), $(I `dpfail`), and $(I `dppass`) parameters; one affects back-facing polygons, and the other affects front-facing polygons as well as other non-polygon primitives. $(REF stencilOp) sets both front and back stencil state to the same values. Use $(REF stencilOpSeparate) to set front and back stencil state to different values.
	
	$(REF stencilOp) takes three arguments that indicate what happens to the stored stencil value while stenciling is enabled. If the stencil test fails, no change is made to the pixel's color or depth buffers, and $(I `sfail`) specifies what happens to the stencil buffer contents. The following eight actions are possible.
	
	- `KEEP`: Keeps the current value.
	
	- `ZERO`: Sets the stencil buffer value to 0.
	
	- `REPLACE`: Sets the stencil buffer value to $(I ref), as specified by $(REF stencilFunc).
	
	- `INCR`: Increments the current stencil buffer value. Clamps to the maximum representable unsigned value.
	
	- `INCR_WRAP`: Increments the current stencil buffer value. Wraps stencil buffer value to zero when incrementing the maximum representable unsigned value.
	
	- `DECR`: Decrements the current stencil buffer value. Clamps to 0.
	
	- `DECR_WRAP`: Decrements the current stencil buffer value. Wraps stencil buffer value to the maximum representable unsigned value when decrementing a stencil buffer value of zero.
	
	- `INVERT`: Bitwise inverts the current stencil buffer value.
	
	Stencil buffer values are treated as unsigned integers. When incremented and decremented, values are clamped to 0 and 2n - 1, where n is the value returned by querying `STENCIL_BITS`.
	
	The other two arguments to $(REF stencilOp) specify stencil buffer actions that depend on whether subsequent depth buffer tests succeed ($(I `dppass`)) or fail ($(I `dpfail`)) (see $(REF depthFunc)). The actions are specified using the same eight symbolic constants as $(I `sfail`). Note that $(I `dpfail`) is ignored when there is no depth buffer, or when the depth buffer is not enabled. In these cases, $(I `sfail`) and $(I `dppass`) specify stencil action when the stencil test fails and passes, respectively.
	
	Params:
	sfail = Specifies the action to take when the stencil test fails. Eight symbolic constants are accepted: `KEEP`, `ZERO`, `REPLACE`, `INCR`, `INCR_WRAP`, `DECR`, `DECR_WRAP`, and `INVERT`. The initial value is `KEEP`.
	dpfail = Specifies the stencil action when the stencil test passes, but the depth test fails. $(I `dpfail`) accepts the same symbolic constants as $(I `sfail`). The initial value is `KEEP`.
	dppass = Specifies the stencil action when both the stencil test and the depth test pass, or when the stencil test passes and either there is no depth buffer or depth testing is not enabled. $(I `dppass`) accepts the same symbolic constants as $(I `sfail`). The initial value is `KEEP`.
	*/
	void stencilOp(Enum sfail, Enum dpfail, Enum dppass);
	
	/**
	$(REF depthFunc) specifies the function used to compare each incoming pixel depth value with the depth value present in the depth buffer. The comparison is performed only if depth testing is enabled. (See $(REF enable) and $(REF disable) of `DEPTH_TEST`.)
	
	$(I `func`) specifies the conditions under which the pixel will be drawn. The comparison functions are as follows:
	
	- `NEVER`: Never passes.
	
	- `LESS`: Passes if the incoming depth value is less than the stored depth value.
	
	- `EQUAL`: Passes if the incoming depth value is equal to the stored depth value.
	
	- `LEQUAL`: Passes if the incoming depth value is less than or equal to the stored depth value.
	
	- `GREATER`: Passes if the incoming depth value is greater than the stored depth value.
	
	- `NOTEQUAL`: Passes if the incoming depth value is not equal to the stored depth value.
	
	- `GEQUAL`: Passes if the incoming depth value is greater than or equal to the stored depth value.
	
	- `ALWAYS`: Always passes.
	
	The initial value of $(I `func`) is `LESS`. Initially, depth testing is disabled. If depth testing is disabled or if no depth buffer exists, it is as if the depth test always passes.
	
	Params:
	func = Specifies the depth comparison function. Symbolic constants `NEVER`, `LESS`, `EQUAL`, `LEQUAL`, `GREATER`, `NOTEQUAL`, `GEQUAL`, and `ALWAYS` are accepted. The initial value is `LESS`.
	*/
	void depthFunc(Enum func);
	
	/**
	$(REF pixelStore) sets pixel storage modes that affect the operation of subsequent $(REF readPixels) as well as the unpacking of texture patterns (see $(REF texImage1D), $(REF texImage2D), $(REF texImage3D), $(REF texSubImage1D), $(REF texSubImage2D), $(REF texSubImage3D)), $(REF compressedTexImage1D), $(REF compressedTexImage2D), $(REF compressedTexImage3D), $(REF compressedTexSubImage1D), $(REF compressedTexSubImage2D) or $(REF compressedTexSubImage1D).
	
	$(I `pname`) is a symbolic constant indicating the parameter to be set, and $(I `param`) is the new value. Six of the twelve storage parameters affect how pixel data is returned to client memory. They are as follows:
	
	- `PACK_SWAP_BYTES`: If true, byte ordering for multibyte color components, depth components, or stencil indices is reversed. That is, if a four-byte component consists of bytes  b 0  ,  b 1  ,  b 2  ,  b 3  , it is stored in memory as  b 3  ,  b 2  ,  b 1  ,  b 0   if `PACK_SWAP_BYTES` is true. `PACK_SWAP_BYTES` has no effect on the memory order of components within a pixel, only on the order of bytes within components or indices. For example, the three components of a `RGB` format pixel are always stored with red first, green second, and blue third, regardless of the value of `PACK_SWAP_BYTES`.
	
	- `PACK_LSB_FIRST`: If true, bits are ordered within a byte from least significant to most significant; otherwise, the first bit in each byte is the most significant one.
	
	- `PACK_ROW_LENGTH`: If greater than 0, `PACK_ROW_LENGTH` defines the number of pixels in a row. If the first pixel of a row is placed at location p in memory, then the location of the first pixel of the next row is obtained by skipping       k =      n ⁢ l       a s   ⁢     s ⁢ n ⁢ l   a      ⁢    s >= a     s < a            components or indices, where n is the number of components or indices in a pixel, l is the number of pixels in a row (`PACK_ROW_LENGTH` if it is greater than 0, the width argument to the pixel routine otherwise), a is the value of `PACK_ALIGNMENT`, and s is the size, in bytes, of a single component (if   a < s  , then it is as if   a = s  ). In the case of 1-bit values, the location of the next row is obtained by skipping     k =  8 ⁢ a ⁢     n ⁢ l     8 ⁢ a          components or indices.   The word $(I component) in this description refers to the nonindex values red, green, blue, alpha, and depth. Storage format `RGB`, for example, has three components per pixel: first red, then green, and finally blue.
	
	- `PACK_IMAGE_HEIGHT`: If greater than 0, `PACK_IMAGE_HEIGHT` defines the number of pixels in an image three-dimensional texture volume, where $(BACKTICK)$(BACKTICK)image'' is defined by all pixels sharing the same third dimension index. If the first pixel of a row is placed at location p in memory, then the location of the first pixel of the next row is obtained by skipping       k =      n ⁢ l ⁢ h       a s   ⁢     s ⁢ n ⁢ l ⁢ h   a      ⁢    s >= a     s < a            components or indices, where n is the number of components or indices in a pixel, l is the number of pixels in a row (`PACK_ROW_LENGTH` if it is greater than 0, the width argument to $(REF texImage3D) otherwise), h is the number of rows in a pixel image (`PACK_IMAGE_HEIGHT` if it is greater than 0, the height argument to the $(REF texImage3D) routine otherwise), a is the value of `PACK_ALIGNMENT`, and s is the size, in bytes, of a single component (if   a < s  , then it is as if   a = s  ).   The word $(I component) in this description refers to the nonindex values red, green, blue, alpha, and depth. Storage format `RGB`, for example, has three components per pixel: first red, then green, and finally blue.
	
	- `PACK_SKIP_PIXELS`, `PACK_SKIP_ROWS`, and `PACK_SKIP_IMAGES`: These values are provided as a convenience to the programmer; they provide no functionality that cannot be duplicated simply by incrementing the pointer passed to $(REF readPixels). Setting `PACK_SKIP_PIXELS` to i is equivalent to incrementing the pointer by   i ⁢ n   components or indices, where n is the number of components or indices in each pixel. Setting `PACK_SKIP_ROWS` to j is equivalent to incrementing the pointer by   j ⁢ m   components or indices, where m is the number of components or indices per row, as just computed in the `PACK_ROW_LENGTH` section. Setting `PACK_SKIP_IMAGES` to k is equivalent to incrementing the pointer by   k ⁢ p  , where p is the number of components or indices per image, as computed in the `PACK_IMAGE_HEIGHT` section.
	
	- `PACK_ALIGNMENT`: Specifies the alignment requirements for the start of each pixel row in memory. The allowable values are 1 (byte-alignment), 2 (rows aligned to even-numbered bytes), 4 (word-alignment), and 8 (rows start on double-word boundaries).
	
	The other six of the twelve storage parameters affect how pixel data is read from client memory. These values are significant for $(REF texImage1D), $(REF texImage2D), $(REF texImage3D), $(REF texSubImage1D), $(REF texSubImage2D), and $(REF texSubImage3D)
	
	They are as follows:
	
	- `UNPACK_SWAP_BYTES`: If true, byte ordering for multibyte color components, depth components, or stencil indices is reversed. That is, if a four-byte component consists of bytes  b 0  ,  b 1  ,  b 2  ,  b 3  , it is taken from memory as  b 3  ,  b 2  ,  b 1  ,  b 0   if `UNPACK_SWAP_BYTES` is true. `UNPACK_SWAP_BYTES` has no effect on the memory order of components within a pixel, only on the order of bytes within components or indices. For example, the three components of a `RGB` format pixel are always stored with red first, green second, and blue third, regardless of the value of `UNPACK_SWAP_BYTES`.
	
	- `UNPACK_LSB_FIRST`: If true, bits are ordered within a byte from least significant to most significant; otherwise, the first bit in each byte is the most significant one.
	
	- `UNPACK_ROW_LENGTH`: If greater than 0, `UNPACK_ROW_LENGTH` defines the number of pixels in a row. If the first pixel of a row is placed at location p in memory, then the location of the first pixel of the next row is obtained by skipping       k =      n ⁢ l       a s   ⁢     s ⁢ n ⁢ l   a      ⁢    s >= a     s < a            components or indices, where n is the number of components or indices in a pixel, l is the number of pixels in a row (`UNPACK_ROW_LENGTH` if it is greater than 0, the width argument to the pixel routine otherwise), a is the value of `UNPACK_ALIGNMENT`, and s is the size, in bytes, of a single component (if   a < s  , then it is as if   a = s  ). In the case of 1-bit values, the location of the next row is obtained by skipping     k =  8 ⁢ a ⁢     n ⁢ l     8 ⁢ a          components or indices.   The word $(I component) in this description refers to the nonindex values red, green, blue, alpha, and depth. Storage format `RGB`, for example, has three components per pixel: first red, then green, and finally blue.
	
	- `UNPACK_IMAGE_HEIGHT`: If greater than 0, `UNPACK_IMAGE_HEIGHT` defines the number of pixels in an image of a three-dimensional texture volume. Where $(BACKTICK)$(BACKTICK)image'' is defined by all pixel sharing the same third dimension index. If the first pixel of a row is placed at location p in memory, then the location of the first pixel of the next row is obtained by skipping       k =      n ⁢ l ⁢ h       a s   ⁢     s ⁢ n ⁢ l ⁢ h   a      ⁢    s >= a     s < a            components or indices, where n is the number of components or indices in a pixel, l is the number of pixels in a row (`UNPACK_ROW_LENGTH` if it is greater than 0, the width argument to $(REF texImage3D) otherwise), h is the number of rows in an image (`UNPACK_IMAGE_HEIGHT` if it is greater than 0, the height argument to $(REF texImage3D) otherwise), a is the value of `UNPACK_ALIGNMENT`, and s is the size, in bytes, of a single component (if   a < s  , then it is as if   a = s  ).   The word $(I component) in this description refers to the nonindex values red, green, blue, alpha, and depth. Storage format `RGB`, for example, has three components per pixel: first red, then green, and finally blue.
	
	- `UNPACK_SKIP_PIXELS` and `UNPACK_SKIP_ROWS`: These values are provided as a convenience to the programmer; they provide no functionality that cannot be duplicated by incrementing the pointer passed to $(REF texImage1D), $(REF texImage2D), $(REF texSubImage1D) or $(REF texSubImage2D). Setting `UNPACK_SKIP_PIXELS` to i is equivalent to incrementing the pointer by   i ⁢ n   components or indices, where n is the number of components or indices in each pixel. Setting `UNPACK_SKIP_ROWS` to j is equivalent to incrementing the pointer by   j ⁢ k   components or indices, where k is the number of components or indices per row, as just computed in the `UNPACK_ROW_LENGTH` section.
	
	- `UNPACK_ALIGNMENT`: Specifies the alignment requirements for the start of each pixel row in memory. The allowable values are 1 (byte-alignment), 2 (rows aligned to even-numbered bytes), 4 (word-alignment), and 8 (rows start on double-word boundaries).
	
	The following table gives the type, initial value, and range of valid values for each storage parameter that can be set with $(REF pixelStore).
	
	$(REF pixelStoref) can be used to set any pixel store parameter. If the parameter type is boolean, then if $(I `param`) is 0, the parameter is false; otherwise it is set to true. If $(I `pname`) is an integer type parameter, $(I `param`) is rounded to the nearest integer.
	
	Likewise, $(REF pixelStorei) can also be used to set any of the pixel store parameters. Boolean parameters are set to false if $(I `param`) is 0 and true otherwise.
	
	Params:
	pname = Specifies the symbolic name of the parameter to be set. Six values affect the packing of pixel data into memory: `PACK_SWAP_BYTES`, `PACK_LSB_FIRST`, `PACK_ROW_LENGTH`, `PACK_IMAGE_HEIGHT`, `PACK_SKIP_PIXELS`, `PACK_SKIP_ROWS`, `PACK_SKIP_IMAGES`, and `PACK_ALIGNMENT`. Six more affect the unpacking of pixel data $(I from) memory: `UNPACK_SWAP_BYTES`, `UNPACK_LSB_FIRST`, `UNPACK_ROW_LENGTH`, `UNPACK_IMAGE_HEIGHT`, `UNPACK_SKIP_PIXELS`, `UNPACK_SKIP_ROWS`, `UNPACK_SKIP_IMAGES`, and `UNPACK_ALIGNMENT`.
	param = Specifies the value that $(I `pname`) is set to.
	*/
	void pixelStoref(Enum pname, Float param);
	
	/**
	$(REF pixelStore) sets pixel storage modes that affect the operation of subsequent $(REF readPixels) as well as the unpacking of texture patterns (see $(REF texImage1D), $(REF texImage2D), $(REF texImage3D), $(REF texSubImage1D), $(REF texSubImage2D), $(REF texSubImage3D)), $(REF compressedTexImage1D), $(REF compressedTexImage2D), $(REF compressedTexImage3D), $(REF compressedTexSubImage1D), $(REF compressedTexSubImage2D) or $(REF compressedTexSubImage1D).
	
	$(I `pname`) is a symbolic constant indicating the parameter to be set, and $(I `param`) is the new value. Six of the twelve storage parameters affect how pixel data is returned to client memory. They are as follows:
	
	- `PACK_SWAP_BYTES`: If true, byte ordering for multibyte color components, depth components, or stencil indices is reversed. That is, if a four-byte component consists of bytes  b 0  ,  b 1  ,  b 2  ,  b 3  , it is stored in memory as  b 3  ,  b 2  ,  b 1  ,  b 0   if `PACK_SWAP_BYTES` is true. `PACK_SWAP_BYTES` has no effect on the memory order of components within a pixel, only on the order of bytes within components or indices. For example, the three components of a `RGB` format pixel are always stored with red first, green second, and blue third, regardless of the value of `PACK_SWAP_BYTES`.
	
	- `PACK_LSB_FIRST`: If true, bits are ordered within a byte from least significant to most significant; otherwise, the first bit in each byte is the most significant one.
	
	- `PACK_ROW_LENGTH`: If greater than 0, `PACK_ROW_LENGTH` defines the number of pixels in a row. If the first pixel of a row is placed at location p in memory, then the location of the first pixel of the next row is obtained by skipping       k =      n ⁢ l       a s   ⁢     s ⁢ n ⁢ l   a      ⁢    s >= a     s < a            components or indices, where n is the number of components or indices in a pixel, l is the number of pixels in a row (`PACK_ROW_LENGTH` if it is greater than 0, the width argument to the pixel routine otherwise), a is the value of `PACK_ALIGNMENT`, and s is the size, in bytes, of a single component (if   a < s  , then it is as if   a = s  ). In the case of 1-bit values, the location of the next row is obtained by skipping     k =  8 ⁢ a ⁢     n ⁢ l     8 ⁢ a          components or indices.   The word $(I component) in this description refers to the nonindex values red, green, blue, alpha, and depth. Storage format `RGB`, for example, has three components per pixel: first red, then green, and finally blue.
	
	- `PACK_IMAGE_HEIGHT`: If greater than 0, `PACK_IMAGE_HEIGHT` defines the number of pixels in an image three-dimensional texture volume, where $(BACKTICK)$(BACKTICK)image'' is defined by all pixels sharing the same third dimension index. If the first pixel of a row is placed at location p in memory, then the location of the first pixel of the next row is obtained by skipping       k =      n ⁢ l ⁢ h       a s   ⁢     s ⁢ n ⁢ l ⁢ h   a      ⁢    s >= a     s < a            components or indices, where n is the number of components or indices in a pixel, l is the number of pixels in a row (`PACK_ROW_LENGTH` if it is greater than 0, the width argument to $(REF texImage3D) otherwise), h is the number of rows in a pixel image (`PACK_IMAGE_HEIGHT` if it is greater than 0, the height argument to the $(REF texImage3D) routine otherwise), a is the value of `PACK_ALIGNMENT`, and s is the size, in bytes, of a single component (if   a < s  , then it is as if   a = s  ).   The word $(I component) in this description refers to the nonindex values red, green, blue, alpha, and depth. Storage format `RGB`, for example, has three components per pixel: first red, then green, and finally blue.
	
	- `PACK_SKIP_PIXELS`, `PACK_SKIP_ROWS`, and `PACK_SKIP_IMAGES`: These values are provided as a convenience to the programmer; they provide no functionality that cannot be duplicated simply by incrementing the pointer passed to $(REF readPixels). Setting `PACK_SKIP_PIXELS` to i is equivalent to incrementing the pointer by   i ⁢ n   components or indices, where n is the number of components or indices in each pixel. Setting `PACK_SKIP_ROWS` to j is equivalent to incrementing the pointer by   j ⁢ m   components or indices, where m is the number of components or indices per row, as just computed in the `PACK_ROW_LENGTH` section. Setting `PACK_SKIP_IMAGES` to k is equivalent to incrementing the pointer by   k ⁢ p  , where p is the number of components or indices per image, as computed in the `PACK_IMAGE_HEIGHT` section.
	
	- `PACK_ALIGNMENT`: Specifies the alignment requirements for the start of each pixel row in memory. The allowable values are 1 (byte-alignment), 2 (rows aligned to even-numbered bytes), 4 (word-alignment), and 8 (rows start on double-word boundaries).
	
	The other six of the twelve storage parameters affect how pixel data is read from client memory. These values are significant for $(REF texImage1D), $(REF texImage2D), $(REF texImage3D), $(REF texSubImage1D), $(REF texSubImage2D), and $(REF texSubImage3D)
	
	They are as follows:
	
	- `UNPACK_SWAP_BYTES`: If true, byte ordering for multibyte color components, depth components, or stencil indices is reversed. That is, if a four-byte component consists of bytes  b 0  ,  b 1  ,  b 2  ,  b 3  , it is taken from memory as  b 3  ,  b 2  ,  b 1  ,  b 0   if `UNPACK_SWAP_BYTES` is true. `UNPACK_SWAP_BYTES` has no effect on the memory order of components within a pixel, only on the order of bytes within components or indices. For example, the three components of a `RGB` format pixel are always stored with red first, green second, and blue third, regardless of the value of `UNPACK_SWAP_BYTES`.
	
	- `UNPACK_LSB_FIRST`: If true, bits are ordered within a byte from least significant to most significant; otherwise, the first bit in each byte is the most significant one.
	
	- `UNPACK_ROW_LENGTH`: If greater than 0, `UNPACK_ROW_LENGTH` defines the number of pixels in a row. If the first pixel of a row is placed at location p in memory, then the location of the first pixel of the next row is obtained by skipping       k =      n ⁢ l       a s   ⁢     s ⁢ n ⁢ l   a      ⁢    s >= a     s < a            components or indices, where n is the number of components or indices in a pixel, l is the number of pixels in a row (`UNPACK_ROW_LENGTH` if it is greater than 0, the width argument to the pixel routine otherwise), a is the value of `UNPACK_ALIGNMENT`, and s is the size, in bytes, of a single component (if   a < s  , then it is as if   a = s  ). In the case of 1-bit values, the location of the next row is obtained by skipping     k =  8 ⁢ a ⁢     n ⁢ l     8 ⁢ a          components or indices.   The word $(I component) in this description refers to the nonindex values red, green, blue, alpha, and depth. Storage format `RGB`, for example, has three components per pixel: first red, then green, and finally blue.
	
	- `UNPACK_IMAGE_HEIGHT`: If greater than 0, `UNPACK_IMAGE_HEIGHT` defines the number of pixels in an image of a three-dimensional texture volume. Where $(BACKTICK)$(BACKTICK)image'' is defined by all pixel sharing the same third dimension index. If the first pixel of a row is placed at location p in memory, then the location of the first pixel of the next row is obtained by skipping       k =      n ⁢ l ⁢ h       a s   ⁢     s ⁢ n ⁢ l ⁢ h   a      ⁢    s >= a     s < a            components or indices, where n is the number of components or indices in a pixel, l is the number of pixels in a row (`UNPACK_ROW_LENGTH` if it is greater than 0, the width argument to $(REF texImage3D) otherwise), h is the number of rows in an image (`UNPACK_IMAGE_HEIGHT` if it is greater than 0, the height argument to $(REF texImage3D) otherwise), a is the value of `UNPACK_ALIGNMENT`, and s is the size, in bytes, of a single component (if   a < s  , then it is as if   a = s  ).   The word $(I component) in this description refers to the nonindex values red, green, blue, alpha, and depth. Storage format `RGB`, for example, has three components per pixel: first red, then green, and finally blue.
	
	- `UNPACK_SKIP_PIXELS` and `UNPACK_SKIP_ROWS`: These values are provided as a convenience to the programmer; they provide no functionality that cannot be duplicated by incrementing the pointer passed to $(REF texImage1D), $(REF texImage2D), $(REF texSubImage1D) or $(REF texSubImage2D). Setting `UNPACK_SKIP_PIXELS` to i is equivalent to incrementing the pointer by   i ⁢ n   components or indices, where n is the number of components or indices in each pixel. Setting `UNPACK_SKIP_ROWS` to j is equivalent to incrementing the pointer by   j ⁢ k   components or indices, where k is the number of components or indices per row, as just computed in the `UNPACK_ROW_LENGTH` section.
	
	- `UNPACK_ALIGNMENT`: Specifies the alignment requirements for the start of each pixel row in memory. The allowable values are 1 (byte-alignment), 2 (rows aligned to even-numbered bytes), 4 (word-alignment), and 8 (rows start on double-word boundaries).
	
	The following table gives the type, initial value, and range of valid values for each storage parameter that can be set with $(REF pixelStore).
	
	$(REF pixelStoref) can be used to set any pixel store parameter. If the parameter type is boolean, then if $(I `param`) is 0, the parameter is false; otherwise it is set to true. If $(I `pname`) is an integer type parameter, $(I `param`) is rounded to the nearest integer.
	
	Likewise, $(REF pixelStorei) can also be used to set any of the pixel store parameters. Boolean parameters are set to false if $(I `param`) is 0 and true otherwise.
	
	Params:
	pname = Specifies the symbolic name of the parameter to be set. Six values affect the packing of pixel data into memory: `PACK_SWAP_BYTES`, `PACK_LSB_FIRST`, `PACK_ROW_LENGTH`, `PACK_IMAGE_HEIGHT`, `PACK_SKIP_PIXELS`, `PACK_SKIP_ROWS`, `PACK_SKIP_IMAGES`, and `PACK_ALIGNMENT`. Six more affect the unpacking of pixel data $(I from) memory: `UNPACK_SWAP_BYTES`, `UNPACK_LSB_FIRST`, `UNPACK_ROW_LENGTH`, `UNPACK_IMAGE_HEIGHT`, `UNPACK_SKIP_PIXELS`, `UNPACK_SKIP_ROWS`, `UNPACK_SKIP_IMAGES`, and `UNPACK_ALIGNMENT`.
	param = Specifies the value that $(I `pname`) is set to.
	*/
	void pixelStorei(Enum pname, Int param);
	
	/**
	$(REF readBuffer) specifies a color buffer as the source for subsequent $(REF readPixels), $(REF copyTexImage1D), $(REF copyTexImage2D), $(REF copyTexSubImage1D), $(REF copyTexSubImage2D), and $(REF copyTexSubImage3D) commands. $(I `mode`) accepts one of twelve or more predefined values. In a fully configured system, `FRONT`, `LEFT`, and `FRONT_LEFT` all name the front left buffer, `FRONT_RIGHT` and `RIGHT` name the front right buffer, and `BACK_LEFT` and `BACK` name the back left buffer. Further more, the constants `COLOR_ATTACHMENT`$(I i) may be used to indicate the $(I i)th color attachment where $(I i) ranges from zero to the value of `MAX_COLOR_ATTACHMENTS` minus one.
	
	Nonstereo double-buffered configurations have only a front left and a back left buffer. Single-buffered configurations have a front left and a front right buffer if stereo, and only a front left buffer if nonstereo. It is an error to specify a nonexistent buffer to $(REF readBuffer).
	
	$(I `mode`) is initially `FRONT` in single-buffered configurations and `BACK` in double-buffered configurations.
	
	For $(REF readBuffer), the target framebuffer object is that bound to `READ_FRAMEBUFFER`. For $(REF namedFramebufferReadBuffer), $(I `framebuffer`) must either be zero or the name of the target framebuffer object. If $(I `framebuffer`) is zero, then the default read framebuffer is affected.
	
	Params:
	mode = Specifies a color buffer. Accepted values are `FRONT_LEFT`, `FRONT_RIGHT`, `BACK_LEFT`, `BACK_RIGHT`, `FRONT`, `BACK`, `LEFT`, `RIGHT`, and the constants `COLOR_ATTACHMENT`$(I i).
	*/
	void readBuffer(Enum mode);
	
	/**
	$(REF readPixels) and $(REF readnPixels) return pixel data from the frame buffer, starting with the pixel whose lower left corner is at location ($(I `x`), $(I `y`)), into client memory starting at location $(I `data`). Several parameters control the processing of the pixel data before it is placed into client memory. These parameters are set with $(REF pixelStore). This reference page describes the effects on $(REF readPixels) and $(REF readnPixels) of most, but not all of the parameters specified by these three commands.
	
	If a non-zero named buffer object is bound to the `PIXEL_PACK_BUFFER` target (see $(REF bindBuffer)) while a block of pixels is requested, $(I `data`) is treated as a byte offset into the buffer object's data store rather than a pointer to client memory.
	
	$(REF readPixels) and $(REF readnPixels) return values from each pixel with lower left corner at (x + i, y + j) for 0 <= i < width and 0 <= j < height. This pixel is said to be the ith pixel in the jth row. Pixels are returned in row order from the lowest to the highest row, left to right in each row.
	
	$(I `format`) specifies the format for the returned pixel values; accepted values are:
	
	- `STENCIL_INDEX`: Stencil values are read from the stencil buffer.
	
	- `DEPTH_COMPONENT`: Depth values are read from the depth buffer. Each component is converted to floating point such that the minimum depth value maps to 0 and the maximum value maps to 1. Each component is clamped to the range   0 1  .
	
	- `DEPTH_STENCIL`: Values are taken from both the depth and stencil buffers. The $(I `type`) parameter must be `UNSIGNED_INT_24_8` or `FLOAT_32_UNSIGNED_INT_24_8_REV`.
	
	- `RED`, `GREEN`, `BLUE`, `RGB`, `BGR`, `RGBA`, `BGRA`: Color values are taken from the color buffer.
	
	Finally, the indices or components are converted to the proper format, as specified by $(I `type`). If $(I `format`) is `STENCIL_INDEX` and $(I `type`) is not `FLOAT`, each index is masked with the mask value given in the following table. If $(I `type`) is `FLOAT`, then each integer index is converted to single-precision floating-point format.
	
	If $(I `format`) is `RED`, `GREEN`, `BLUE`, `RGB`, `BGR`, `RGBA`, or `BGRA` and $(I `type`) is not `FLOAT`, each component is multiplied by the multiplier shown in the following table. If type is `FLOAT`, then each component is passed as is (or converted to the client's single-precision floating-point format if it is different from the one used by the GL).
	
	Return values are placed in memory as follows. If $(I `format`) is `STENCIL_INDEX`, `DEPTH_COMPONENT`, `RED`, `GREEN`, or `BLUE`, a single value is returned and the data for the ith pixel in the jth row is placed in location (j)⁢width + i. `RGB` and `BGR` return three values, `RGBA` and `BGRA` return four values for each pixel, with all values corresponding to a single pixel occupying contiguous space in $(I `data`). Storage parameters set by $(REF pixelStore), such as `PACK_LSB_FIRST` and `PACK_SWAP_BYTES`, affect the way that data is written into memory. See $(REF pixelStore) for a description.
	
	$(REF readnPixels) function will only handle the call if $(I `bufSize`) is at least of the size required to store the requested data. Otherwise, it will generate a `INVALID_OPERATION` error.
	
	Params:
	x = Specify the window coordinates of the first pixel that is read from the frame buffer. This location is the lower left corner of a rectangular block of pixels.
	y = Specify the window coordinates of the first pixel that is read from the frame buffer. This location is the lower left corner of a rectangular block of pixels.
	width = Specify the dimensions of the pixel rectangle. $(I `width`) and $(I `height`) of one correspond to a single pixel.
	height = Specify the dimensions of the pixel rectangle. $(I `width`) and $(I `height`) of one correspond to a single pixel.
	format = Specifies the format of the pixel data. The following symbolic values are accepted: `STENCIL_INDEX`, `DEPTH_COMPONENT`, `DEPTH_STENCIL`, `RED`, `GREEN`, `BLUE`, `RGB`, `BGR`, `RGBA`, and `BGRA`.
	type = Specifies the data type of the pixel data. Must be one of `UNSIGNED_BYTE`, `BYTE`, `UNSIGNED_SHORT`, `SHORT`, `UNSIGNED_INT`, `INT`, `HALF_FLOAT`, `FLOAT`, `UNSIGNED_BYTE_3_3_2`, `UNSIGNED_BYTE_2_3_3_REV`, `UNSIGNED_SHORT_5_6_5`, `UNSIGNED_SHORT_5_6_5_REV`, `UNSIGNED_SHORT_4_4_4_4`, `UNSIGNED_SHORT_4_4_4_4_REV`, `UNSIGNED_SHORT_5_5_5_1`, `UNSIGNED_SHORT_1_5_5_5_REV`, `UNSIGNED_INT_8_8_8_8`, `UNSIGNED_INT_8_8_8_8_REV`, `UNSIGNED_INT_10_10_10_2`, `UNSIGNED_INT_2_10_10_10_REV`, `UNSIGNED_INT_24_8`, `UNSIGNED_INT_10F_11F_11F_REV`, `UNSIGNED_INT_5_9_9_9_REV`, or `FLOAT_32_UNSIGNED_INT_24_8_REV`.
	data = Returns the pixel data.
	*/
	void readPixels(Int x, Int y, Sizei width, Sizei height, Enum format, Enum type, void* data);
	
	/**
	These commands return values for simple state variables in GL. $(I `pname`) is a symbolic constant indicating the state variable to be returned, and $(I `data`) is a pointer to an array of the indicated type in which to place the returned data.
	
	Type conversion is performed if $(I `data`) has a different type than the state variable value being requested. If $(REF getBooleanv) is called, a floating-point (or integer) value is converted to `FALSE` if and only if it is 0.0 (or 0). Otherwise, it is converted to `TRUE`. If $(REF getIntegerv) is called, boolean values are returned as `TRUE` or `FALSE`, and most floating-point values are rounded to the nearest integer value. Floating-point colors and normals, however, are returned with a linear mapping that maps 1.0 to the most positive representable integer value and -1.0 to the most negative representable integer value. If $(REF getFloatv) or $(REF getDoublev) is called, boolean values are returned as `TRUE` or `FALSE`, and integer values are converted to floating-point values.
	
	The following symbolic constants are accepted by $(I `pname`):
	
	- `ACTIVE_TEXTURE`: $(I `data`) returns a single value indicating the active multitexture unit. The initial value is `TEXTURE0`. See $(REF activeTexture).
	
	- `ALIASED_LINE_WIDTH_RANGE`: $(I `data`) returns a pair of values indicating the range of widths supported for aliased lines. See $(REF lineWidth).
	
	- `ARRAY_BUFFER_BINDING`: $(I `data`) returns a single value, the name of the buffer object currently bound to the target `ARRAY_BUFFER`. If no buffer object is bound to this target, 0 is returned. The initial value is 0. See $(REF bindBuffer).
	
	- `BLEND`: $(I `data`) returns a single boolean value indicating whether blending is enabled. The initial value is `FALSE`. See $(REF blendFunc).
	
	- `BLEND_COLOR`: $(I `data`) returns four values, the red, green, blue, and alpha values which are the components of the blend color. See $(REF blendColor).
	
	- `BLEND_DST_ALPHA`: $(I `data`) returns one value, the symbolic constant identifying the alpha destination blend function. The initial value is `ZERO`. See $(REF blendFunc) and $(REF blendFuncSeparate).
	
	- `BLEND_DST_RGB`: $(I `data`) returns one value, the symbolic constant identifying the RGB destination blend function. The initial value is `ZERO`. See $(REF blendFunc) and $(REF blendFuncSeparate).
	
	- `BLEND_EQUATION_RGB`: $(I `data`) returns one value, a symbolic constant indicating whether the RGB blend equation is `FUNC_ADD`, `FUNC_SUBTRACT`, `FUNC_REVERSE_SUBTRACT`, `MIN` or `MAX`. See $(REF blendEquationSeparate).
	
	- `BLEND_EQUATION_ALPHA`: $(I `data`) returns one value, a symbolic constant indicating whether the Alpha blend equation is `FUNC_ADD`, `FUNC_SUBTRACT`, `FUNC_REVERSE_SUBTRACT`, `MIN` or `MAX`. See $(REF blendEquationSeparate).
	
	- `BLEND_SRC_ALPHA`: $(I `data`) returns one value, the symbolic constant identifying the alpha source blend function. The initial value is `ONE`. See $(REF blendFunc) and $(REF blendFuncSeparate).
	
	- `BLEND_SRC_RGB`: $(I `data`) returns one value, the symbolic constant identifying the RGB source blend function. The initial value is `ONE`. See $(REF blendFunc) and $(REF blendFuncSeparate).
	
	- `COLOR_CLEAR_VALUE`: $(I `data`) returns four values: the red, green, blue, and alpha values used to clear the color buffers. Integer values, if requested, are linearly mapped from the internal floating-point representation such that 1.0 returns the most positive representable integer value, and  -1.0  returns the most negative representable integer value. The initial value is (0, 0, 0, 0). See $(REF clearColor).
	
	- `COLOR_LOGIC_OP`: $(I `data`) returns a single boolean value indicating whether a fragment's RGBA color values are merged into the framebuffer using a logical operation. The initial value is `FALSE`. See $(REF logicOp).
	
	- `COLOR_WRITEMASK`: $(I `data`) returns four boolean values: the red, green, blue, and alpha write enables for the color buffers. The initial value is (`TRUE`, `TRUE`, `TRUE`, `TRUE`). See $(REF colorMask).
	
	- `COMPRESSED_TEXTURE_FORMATS`: $(I `data`) returns a list of symbolic constants of length `NUM_COMPRESSED_TEXTURE_FORMATS` indicating which compressed texture formats are available. See $(REF compressedTexImage2D).
	
	- `MAX_COMPUTE_SHADER_STORAGE_BLOCKS`: $(I `data`) returns one value, the maximum number of active shader storage blocks that may be accessed by a compute shader.
	
	- `MAX_COMBINED_SHADER_STORAGE_BLOCKS`: $(I `data`) returns one value, the maximum total number of active shader storage blocks that may be accessed by all active shaders.
	
	- `MAX_COMPUTE_UNIFORM_BLOCKS`: $(I `data`) returns one value, the maximum number of uniform blocks per compute shader. The value must be at least 14. See $(REF uniformBlockBinding).
	
	- `MAX_COMPUTE_TEXTURE_IMAGE_UNITS`: $(I `data`) returns one value, the maximum supported texture image units that can be used to access texture maps from the compute shader. The value may be at least 16. See $(REF activeTexture).
	
	- `MAX_COMPUTE_UNIFORM_COMPONENTS`: $(I `data`) returns one value, the maximum number of individual floating-point, integer, or boolean values that can be held in uniform variable storage for a compute shader. The value must be at least 1024. See $(REF uniform).
	
	- `MAX_COMPUTE_ATOMIC_COUNTERS`: $(I `data`) returns a single value, the maximum number of atomic counters available to compute shaders.
	
	- `MAX_COMPUTE_ATOMIC_COUNTER_BUFFERS`: $(I `data`) returns a single value, the maximum number of atomic counter buffers that may be accessed by a compute shader.
	
	- `MAX_COMBINED_COMPUTE_UNIFORM_COMPONENTS`: $(I `data`) returns one value, the number of words for compute shader uniform variables in all uniform blocks (including default). The value must be at least 1. See $(REF uniform).
	
	- `MAX_COMPUTE_WORK_GROUP_INVOCATIONS`: $(I `data`) returns one value, the number of invocations in a single local work group (i.e., the product of the three dimensions) that may be dispatched to a compute shader.
	
	- `MAX_COMPUTE_WORK_GROUP_COUNT`: Accepted by the indexed versions of $(REF get). $(I `data`) the maximum number of work groups that may be dispatched to a compute shader. Indices 0, 1, and 2 correspond to the X, Y and Z dimensions, respectively.
	
	- `MAX_COMPUTE_WORK_GROUP_SIZE`: Accepted by the indexed versions of $(REF get). $(I `data`) the maximum size of a work groups that may be used during compilation of a compute shader. Indices 0, 1, and 2 correspond to the X, Y and Z dimensions, respectively.
	
	- `DISPATCH_INDIRECT_BUFFER_BINDING`: $(I `data`) returns a single value, the name of the buffer object currently bound to the target `DISPATCH_INDIRECT_BUFFER`. If no buffer object is bound to this target, 0 is returned. The initial value is 0. See $(REF bindBuffer).
	
	- `MAX_DEBUG_GROUP_STACK_DEPTH`: $(I `data`) returns a single value, the maximum depth of the debug message group stack.
	
	- `DEBUG_GROUP_STACK_DEPTH`: $(I `data`) returns a single value, the current depth of the debug message group stack.
	
	- `CONTEXT_FLAGS`: $(I `data`) returns one value, the flags with which the context was created (such as debugging functionality).
	
	- `CULL_FACE`: $(I `data`) returns a single boolean value indicating whether polygon culling is enabled. The initial value is `FALSE`. See $(REF cullFace).
	
	- `CULL_FACE_MODE`: $(I `data`) returns a single value indicating the mode of polygon culling. The initial value is `BACK`. See $(REF cullFace).
	
	- `CURRENT_PROGRAM`: $(I `data`) returns one value, the name of the program object that is currently active, or 0 if no program object is active. See $(REF useProgram).
	
	- `DEPTH_CLEAR_VALUE`: $(I `data`) returns one value, the value that is used to clear the depth buffer. Integer values, if requested, are linearly mapped from the internal floating-point representation such that 1.0 returns the most positive representable integer value, and  -1.0  returns the most negative representable integer value. The initial value is 1. See $(REF clearDepth).
	
	- `DEPTH_FUNC`: $(I `data`) returns one value, the symbolic constant that indicates the depth comparison function. The initial value is `LESS`. See $(REF depthFunc).
	
	- `DEPTH_RANGE`: $(I `data`) returns two values: the near and far mapping limits for the depth buffer. Integer values, if requested, are linearly mapped from the internal floating-point representation such that 1.0 returns the most positive representable integer value, and  -1.0  returns the most negative representable integer value. The initial value is (0, 1). See $(REF depthRange).
	
	- `DEPTH_TEST`: $(I `data`) returns a single boolean value indicating whether depth testing of fragments is enabled. The initial value is `FALSE`. See $(REF depthFunc) and $(REF depthRange).
	
	- `DEPTH_WRITEMASK`: $(I `data`) returns a single boolean value indicating if the depth buffer is enabled for writing. The initial value is `TRUE`. See $(REF depthMask).
	
	- `DITHER`: $(I `data`) returns a single boolean value indicating whether dithering of fragment colors and indices is enabled. The initial value is `TRUE`.
	
	- `DOUBLEBUFFER`: $(I `data`) returns a single boolean value indicating whether double buffering is supported.
	
	- `DRAW_BUFFER`: $(I `data`) returns one value, a symbolic constant indicating which buffers are being drawn to. See $(REF drawBuffer). The initial value is `BACK` if there are back buffers, otherwise it is `FRONT`.
	
	- `DRAW_BUFFER`  $(I i): $(I `data`) returns one value, a symbolic constant indicating which buffers are being drawn to by the corresponding output color. See $(REF drawBuffers). The initial value of `DRAW_BUFFER0` is `BACK` if there are back buffers, otherwise it is `FRONT`. The initial values of draw buffers for all other output colors is `NONE`.
	
	- `DRAW_FRAMEBUFFER_BINDING`: $(I `data`) returns one value, the name of the framebuffer object currently bound to the `DRAW_FRAMEBUFFER` target. If the default framebuffer is bound, this value will be zero. The initial value is zero. See $(REF bindFramebuffer).
	
	- `READ_FRAMEBUFFER_BINDING`: $(I `data`) returns one value, the name of the framebuffer object currently bound to the `READ_FRAMEBUFFER` target. If the default framebuffer is bound, this value will be zero. The initial value is zero. See $(REF bindFramebuffer).
	
	- `ELEMENT_ARRAY_BUFFER_BINDING`: $(I `data`) returns a single value, the name of the buffer object currently bound to the target `ELEMENT_ARRAY_BUFFER`. If no buffer object is bound to this target, 0 is returned. The initial value is 0. See $(REF bindBuffer).
	
	- `FRAGMENT_SHADER_DERIVATIVE_HINT`: $(I `data`) returns one value, a symbolic constant indicating the mode of the derivative accuracy hint for fragment shaders. The initial value is `DONT_CARE`. See $(REF hint).
	
	- `IMPLEMENTATION_COLOR_READ_FORMAT`: $(I `data`) returns a single GLenum value indicating the implementation's preferred pixel data format. See $(REF readPixels).
	
	- `IMPLEMENTATION_COLOR_READ_TYPE`: $(I `data`) returns a single GLenum value indicating the implementation's preferred pixel data type. See $(REF readPixels).
	
	- `LINE_SMOOTH`: $(I `data`) returns a single boolean value indicating whether antialiasing of lines is enabled. The initial value is `FALSE`. See $(REF lineWidth).
	
	- `LINE_SMOOTH_HINT`: $(I `data`) returns one value, a symbolic constant indicating the mode of the line antialiasing hint. The initial value is `DONT_CARE`. See $(REF hint).
	
	- `LINE_WIDTH`: $(I `data`) returns one value, the line width as specified with $(REF lineWidth). The initial value is 1.
	
	- `LAYER_PROVOKING_VERTEX`: $(I `data`) returns one value, the implementation dependent specifc vertex of a primitive that is used to select the rendering layer. If the value returned is equivalent to `PROVOKING_VERTEX`, then the vertex selection follows the convention specified by $(REF provokingVertex). If the value returned is equivalent to `FIRST_VERTEX_CONVENTION`, then the selection is always taken from the first vertex in the primitive. If the value returned is equivalent to `LAST_VERTEX_CONVENTION`, then the selection is always taken from the last vertex in the primitive. If the value returned is equivalent to `UNDEFINED_VERTEX`, then the selection is not guaranteed to be taken from any specific vertex in the primitive.
	
	- `LOGIC_OP_MODE`: $(I `data`) returns one value, a symbolic constant indicating the selected logic operation mode. The initial value is `COPY`. See $(REF logicOp).
	
	- `MAJOR_VERSION`: $(I `data`) returns one value, the major version number of the OpenGL API supported by the current context.
	
	- `MAX_3D_TEXTURE_SIZE`: $(I `data`) returns one value, a rough estimate of the largest 3D texture that the GL can handle. The value must be at least 64. Use `PROXY_TEXTURE_3D` to determine if a texture is too large. See $(REF texImage3D).
	
	- `MAX_ARRAY_TEXTURE_LAYERS`: $(I `data`) returns one value. The value indicates the maximum number of layers allowed in an array texture, and must be at least 256. See $(REF texImage2D).
	
	- `MAX_CLIP_DISTANCES`: $(I `data`) returns one value, the maximum number of application-defined clipping distances. The value must be at least 8.
	
	- `MAX_COLOR_TEXTURE_SAMPLES`: $(I `data`) returns one value, the maximum number of samples in a color multisample texture.
	
	- `MAX_COMBINED_ATOMIC_COUNTERS`: $(I `data`) returns a single value, the maximum number of atomic counters available to all active shaders.
	
	- `MAX_COMBINED_FRAGMENT_UNIFORM_COMPONENTS`: $(I `data`) returns one value, the number of words for fragment shader uniform variables in all uniform blocks (including default). The value must be at least 1. See $(REF uniform).
	
	- `MAX_COMBINED_GEOMETRY_UNIFORM_COMPONENTS`: $(I `data`) returns one value, the number of words for geometry shader uniform variables in all uniform blocks (including default). The value must be at least 1. See $(REF uniform).
	
	- `MAX_COMBINED_TEXTURE_IMAGE_UNITS`: $(I `data`) returns one value, the maximum supported texture image units that can be used to access texture maps from the vertex shader and the fragment processor combined. If both the vertex shader and the fragment processing stage access the same texture image unit, then that counts as using two texture image units against this limit. The value must be at least 48. See $(REF activeTexture).
	
	- `MAX_COMBINED_UNIFORM_BLOCKS`: $(I `data`) returns one value, the maximum number of uniform blocks per program. The value must be at least 70. See $(REF uniformBlockBinding).
	
	- `MAX_COMBINED_VERTEX_UNIFORM_COMPONENTS`: $(I `data`) returns one value, the number of words for vertex shader uniform variables in all uniform blocks (including default). The value must be at least 1. See $(REF uniform).
	
	- `MAX_CUBE_MAP_TEXTURE_SIZE`: $(I `data`) returns one value. The value gives a rough estimate of the largest cube-map texture that the GL can handle. The value must be at least 1024. Use `PROXY_TEXTURE_CUBE_MAP` to determine if a texture is too large. See $(REF texImage2D).
	
	- `MAX_DEPTH_TEXTURE_SAMPLES`: $(I `data`) returns one value, the maximum number of samples in a multisample depth or depth-stencil texture.
	
	- `MAX_DRAW_BUFFERS`: $(I `data`) returns one value, the maximum number of simultaneous outputs that may be written in a fragment shader. The value must be at least 8. See $(REF drawBuffers).
	
	- `MAX_DUAL_SOURCE_DRAW_BUFFERS`: $(I `data`) returns one value, the maximum number of active draw buffers when using dual-source blending. The value must be at least 1. See $(REF blendFunc) and $(REF blendFuncSeparate).
	
	- `MAX_ELEMENTS_INDICES`: $(I `data`) returns one value, the recommended maximum number of vertex array indices. See $(REF drawRangeElements).
	
	- `MAX_ELEMENTS_VERTICES`: $(I `data`) returns one value, the recommended maximum number of vertex array vertices. See $(REF drawRangeElements).
	
	- `MAX_FRAGMENT_ATOMIC_COUNTERS`: $(I `data`) returns a single value, the maximum number of atomic counters available to fragment shaders.
	
	- `MAX_FRAGMENT_SHADER_STORAGE_BLOCKS`: $(I `data`) returns one value, the maximum number of active shader storage blocks that may be accessed by a fragment shader.
	
	- `MAX_FRAGMENT_INPUT_COMPONENTS`: $(I `data`) returns one value, the maximum number of components of the inputs read by the fragment shader, which must be at least 128.
	
	- `MAX_FRAGMENT_UNIFORM_COMPONENTS`: $(I `data`) returns one value, the maximum number of individual floating-point, integer, or boolean values that can be held in uniform variable storage for a fragment shader. The value must be at least 1024. See $(REF uniform).
	
	- `MAX_FRAGMENT_UNIFORM_VECTORS`: $(I `data`) returns one value, the maximum number of individual 4-vectors of floating-point, integer, or boolean values that can be held in uniform variable storage for a fragment shader. The value is equal to the value of `MAX_FRAGMENT_UNIFORM_COMPONENTS` divided by 4 and must be at least 256. See $(REF uniform).
	
	- `MAX_FRAGMENT_UNIFORM_BLOCKS`: $(I `data`) returns one value, the maximum number of uniform blocks per fragment shader. The value must be at least 12. See $(REF uniformBlockBinding).
	
	- `MAX_FRAMEBUFFER_WIDTH`: $(I `data`) returns one value, the maximum width for a framebuffer that has no attachments, which must be at least 16384. See $(REF framebufferParameter).
	
	- `MAX_FRAMEBUFFER_HEIGHT`: $(I `data`) returns one value, the maximum height for a framebuffer that has no attachments, which must be at least 16384. See $(REF framebufferParameter).
	
	- `MAX_FRAMEBUFFER_LAYERS`: $(I `data`) returns one value, the maximum number of layers for a framebuffer that has no attachments, which must be at least 2048. See $(REF framebufferParameter).
	
	- `MAX_FRAMEBUFFER_SAMPLES`: $(I `data`) returns one value, the maximum samples in a framebuffer that has no attachments, which must be at least 4. See $(REF framebufferParameter).
	
	- `MAX_GEOMETRY_ATOMIC_COUNTERS`: $(I `data`) returns a single value, the maximum number of atomic counters available to geometry shaders.
	
	- `MAX_GEOMETRY_SHADER_STORAGE_BLOCKS`: $(I `data`) returns one value, the maximum number of active shader storage blocks that may be accessed by a geometry shader.
	
	- `MAX_GEOMETRY_INPUT_COMPONENTS`: $(I `data`) returns one value, the maximum number of components of inputs read by a geometry shader, which must be at least 64.
	
	- `MAX_GEOMETRY_OUTPUT_COMPONENTS`: $(I `data`) returns one value, the maximum number of components of outputs written by a geometry shader, which must be at least 128.
	
	- `MAX_GEOMETRY_TEXTURE_IMAGE_UNITS`: $(I `data`) returns one value, the maximum supported texture image units that can be used to access texture maps from the geometry shader. The value must be at least 16. See $(REF activeTexture).
	
	- `MAX_GEOMETRY_UNIFORM_BLOCKS`: $(I `data`) returns one value, the maximum number of uniform blocks per geometry shader. The value must be at least 12. See $(REF uniformBlockBinding).
	
	- `MAX_GEOMETRY_UNIFORM_COMPONENTS`: $(I `data`) returns one value, the maximum number of individual floating-point, integer, or boolean values that can be held in uniform variable storage for a geometry shader. The value must be at least 1024. See $(REF uniform).
	
	- `MAX_INTEGER_SAMPLES`: $(I `data`) returns one value, the maximum number of samples supported in integer format multisample buffers.
	
	- `MIN_MAP_BUFFER_ALIGNMENT`: $(I `data`) returns one value, the minimum alignment in basic machine units of pointers returned from$(REF mapBuffer) and $(REF mapBufferRange). This value must be a power of two and must be at least 64.
	
	- `MAX_LABEL_LENGTH`: $(I `data`) returns one value, the maximum length of a label that may be assigned to an object. See $(REF objectLabel) and $(REF objectPtrLabel).
	
	- `MAX_PROGRAM_TEXEL_OFFSET`: $(I `data`) returns one value, the maximum texel offset allowed in a texture lookup, which must be at least 7.
	
	- `MIN_PROGRAM_TEXEL_OFFSET`: $(I `data`) returns one value, the minimum texel offset allowed in a texture lookup, which must be at most -8.
	
	- `MAX_RECTANGLE_TEXTURE_SIZE`: $(I `data`) returns one value. The value gives a rough estimate of the largest rectangular texture that the GL can handle. The value must be at least 1024. Use `PROXY_TEXTURE_RECTANGLE` to determine if a texture is too large. See $(REF texImage2D).
	
	- `MAX_RENDERBUFFER_SIZE`: $(I `data`) returns one value. The value indicates the maximum supported size for renderbuffers. See $(REF framebufferRenderbuffer).
	
	- `MAX_SAMPLE_MASK_WORDS`: $(I `data`) returns one value, the maximum number of sample mask words.
	
	- `MAX_SERVER_WAIT_TIMEOUT`: $(I `data`) returns one value, the maximum $(REF waitSync) timeout interval.
	
	- `MAX_SHADER_STORAGE_BUFFER_BINDINGS`: $(I `data`) returns one value, the maximum number of shader storage buffer binding points on the context, which must be at least 8.
	
	- `MAX_TESS_CONTROL_ATOMIC_COUNTERS`: $(I `data`) returns a single value, the maximum number of atomic counters available to tessellation control shaders.
	
	- `MAX_TESS_EVALUATION_ATOMIC_COUNTERS`: $(I `data`) returns a single value, the maximum number of atomic counters available to tessellation evaluation shaders.
	
	- `MAX_TESS_CONTROL_SHADER_STORAGE_BLOCKS`: $(I `data`) returns one value, the maximum number of active shader storage blocks that may be accessed by a tessellation control shader.
	
	- `MAX_TESS_EVALUATION_SHADER_STORAGE_BLOCKS`: $(I `data`) returns one value, the maximum number of active shader storage blocks that may be accessed by a tessellation evaluation shader.
	
	- `MAX_TEXTURE_BUFFER_SIZE`: $(I `data`) returns one value. The value gives the maximum number of texels allowed in the texel array of a texture buffer object. Value must be at least 65536.
	
	- `MAX_TEXTURE_IMAGE_UNITS`: $(I `data`) returns one value, the maximum supported texture image units that can be used to access texture maps from the fragment shader. The value must be at least 16. See $(REF activeTexture).
	
	- `MAX_TEXTURE_LOD_BIAS`: $(I `data`) returns one value, the maximum, absolute value of the texture level-of-detail bias. The value must be at least 2.0.
	
	- `MAX_TEXTURE_SIZE`: $(I `data`) returns one value. The value gives a rough estimate of the largest texture that the GL can handle. The value must be at least 1024. Use a proxy texture target such as `PROXY_TEXTURE_1D` or `PROXY_TEXTURE_2D` to determine if a texture is too large. See $(REF texImage1D) and $(REF texImage2D).
	
	- `MAX_UNIFORM_BUFFER_BINDINGS`: $(I `data`) returns one value, the maximum number of uniform buffer binding points on the context, which must be at least 36.
	
	- `MAX_UNIFORM_BLOCK_SIZE`: $(I `data`) returns one value, the maximum size in basic machine units of a uniform block, which must be at least 16384.
	
	- `MAX_UNIFORM_LOCATIONS`: $(I `data`) returns one value, the maximum number of explicitly assignable uniform locations, which must be at least 1024.
	
	- `MAX_VARYING_COMPONENTS`: $(I `data`) returns one value, the number components for varying variables, which must be at least 60.
	
	- `MAX_VARYING_VECTORS`: $(I `data`) returns one value, the number 4-vectors for varying variables, which is equal to the value of `MAX_VARYING_COMPONENTS` and must be at least 15.
	
	- `MAX_VARYING_FLOATS`: $(I `data`) returns one value, the maximum number of interpolators available for processing varying variables used by vertex and fragment shaders. This value represents the number of individual floating-point values that can be interpolated; varying variables declared as vectors, matrices, and arrays will all consume multiple interpolators. The value must be at least 32.
	
	- `MAX_VERTEX_ATOMIC_COUNTERS`: $(I `data`) returns a single value, the maximum number of atomic counters available to vertex shaders.
	
	- `MAX_VERTEX_ATTRIBS`: $(I `data`) returns one value, the maximum number of 4-component generic vertex attributes accessible to a vertex shader. The value must be at least 16. See $(REF vertexAttrib).
	
	- `MAX_VERTEX_SHADER_STORAGE_BLOCKS`: $(I `data`) returns one value, the maximum number of active shader storage blocks that may be accessed by a vertex shader.
	
	- `MAX_VERTEX_TEXTURE_IMAGE_UNITS`: $(I `data`) returns one value, the maximum supported texture image units that can be used to access texture maps from the vertex shader. The value may be at least 16. See $(REF activeTexture).
	
	- `MAX_VERTEX_UNIFORM_COMPONENTS`: $(I `data`) returns one value, the maximum number of individual floating-point, integer, or boolean values that can be held in uniform variable storage for a vertex shader. The value must be at least 1024. See $(REF uniform).
	
	- `MAX_VERTEX_UNIFORM_VECTORS`: $(I `data`) returns one value, the maximum number of 4-vectors that may be held in uniform variable storage for the vertex shader. The value of `MAX_VERTEX_UNIFORM_VECTORS` is equal to the value of `MAX_VERTEX_UNIFORM_COMPONENTS` and must be at least 256.
	
	- `MAX_VERTEX_OUTPUT_COMPONENTS`: $(I `data`) returns one value, the maximum number of components of output written by a vertex shader, which must be at least 64.
	
	- `MAX_VERTEX_UNIFORM_BLOCKS`: $(I `data`) returns one value, the maximum number of uniform blocks per vertex shader. The value must be at least 12. See $(REF uniformBlockBinding).
	
	- `MAX_VIEWPORT_DIMS`: $(I `data`) returns two values: the maximum supported width and height of the viewport. These must be at least as large as the visible dimensions of the display being rendered to. See $(REF viewport).
	
	- `MAX_VIEWPORTS`: $(I `data`) returns one value, the maximum number of simultaneous viewports that are supported. The value must be at least 16. See $(REF viewportIndexed).
	
	- `MINOR_VERSION`: $(I `data`) returns one value, the minor version number of the OpenGL API supported by the current context.
	
	- `NUM_COMPRESSED_TEXTURE_FORMATS`: $(I `data`) returns a single integer value indicating the number of available compressed texture formats. The minimum value is 4. See $(REF compressedTexImage2D).
	
	- `NUM_EXTENSIONS`: $(I `data`) returns one value, the number of extensions supported by the GL implementation for the current context. See $(REF getString).
	
	- `NUM_PROGRAM_BINARY_FORMATS`: $(I `data`) returns one value, the number of program binary formats supported by the implementation.
	
	- `NUM_SHADER_BINARY_FORMATS`: $(I `data`) returns one value, the number of binary shader formats supported by the implementation. If this value is greater than zero, then the implementation supports loading binary shaders. If it is zero, then the loading of binary shaders by the implementation is not supported.
	
	- `PACK_ALIGNMENT`: $(I `data`) returns one value, the byte alignment used for writing pixel data to memory. The initial value is 4. See $(REF pixelStore).
	
	- `PACK_IMAGE_HEIGHT`: $(I `data`) returns one value, the image height used for writing pixel data to memory. The initial value is 0. See $(REF pixelStore).
	
	- `PACK_LSB_FIRST`: $(I `data`) returns a single boolean value indicating whether single-bit pixels being written to memory are written first to the least significant bit of each unsigned byte. The initial value is `FALSE`. See $(REF pixelStore).
	
	- `PACK_ROW_LENGTH`: $(I `data`) returns one value, the row length used for writing pixel data to memory. The initial value is 0. See $(REF pixelStore).
	
	- `PACK_SKIP_IMAGES`: $(I `data`) returns one value, the number of pixel images skipped before the first pixel is written into memory. The initial value is 0. See $(REF pixelStore).
	
	- `PACK_SKIP_PIXELS`: $(I `data`) returns one value, the number of pixel locations skipped before the first pixel is written into memory. The initial value is 0. See $(REF pixelStore).
	
	- `PACK_SKIP_ROWS`: $(I `data`) returns one value, the number of rows of pixel locations skipped before the first pixel is written into memory. The initial value is 0. See $(REF pixelStore).
	
	- `PACK_SWAP_BYTES`: $(I `data`) returns a single boolean value indicating whether the bytes of two-byte and four-byte pixel indices and components are swapped before being written to memory. The initial value is `FALSE`. See $(REF pixelStore).
	
	- `PIXEL_PACK_BUFFER_BINDING`: $(I `data`) returns a single value, the name of the buffer object currently bound to the target `PIXEL_PACK_BUFFER`. If no buffer object is bound to this target, 0 is returned. The initial value is 0. See $(REF bindBuffer).
	
	- `PIXEL_UNPACK_BUFFER_BINDING`: $(I `data`) returns a single value, the name of the buffer object currently bound to the target `PIXEL_UNPACK_BUFFER`. If no buffer object is bound to this target, 0 is returned. The initial value is 0. See $(REF bindBuffer).
	
	- `POINT_FADE_THRESHOLD_SIZE`: $(I `data`) returns one value, the point size threshold for determining the point size. See $(REF pointParameter).
	
	- `PRIMITIVE_RESTART_INDEX`: $(I `data`) returns one value, the current primitive restart index. The initial value is 0. See $(REF primitiveRestartIndex).
	
	- `PROGRAM_BINARY_FORMATS`: $(I `data`) an array of `NUM_PROGRAM_BINARY_FORMATS` values, indicating the proram binary formats supported by the implementation.
	
	- `PROGRAM_PIPELINE_BINDING`: $(I `data`) a single value, the name of the currently bound program pipeline object, or zero if no program pipeline object is bound. See $(REF bindProgramPipeline).
	
	- `PROGRAM_POINT_SIZE`: $(I `data`) returns a single boolean value indicating whether vertex program point size mode is enabled. If enabled, then the point size is taken from the shader built-in `gl_PointSize`. If disabled, then the point size is taken from the point state as specified by $(REF pointSize). The initial value is `FALSE`.
	
	- `PROVOKING_VERTEX`: $(I `data`) returns one value, the currently selected provoking vertex convention. The initial value is `LAST_VERTEX_CONVENTION`. See $(REF provokingVertex).
	
	- `POINT_SIZE`: $(I `data`) returns one value, the point size as specified by $(REF pointSize). The initial value is 1.
	
	- `POINT_SIZE_GRANULARITY`: $(I `data`) returns one value, the size difference between adjacent supported sizes for antialiased points. See $(REF pointSize).
	
	- `POINT_SIZE_RANGE`: $(I `data`) returns two values: the smallest and largest supported sizes for antialiased points. The smallest size must be at most 1, and the largest size must be at least 1. See $(REF pointSize).
	
	- `POLYGON_OFFSET_FACTOR`: $(I `data`) returns one value, the scaling factor used to determine the variable offset that is added to the depth value of each fragment generated when a polygon is rasterized. The initial value is 0. See $(REF polygonOffset).
	
	- `POLYGON_OFFSET_UNITS`: $(I `data`) returns one value. This value is multiplied by an implementation-specific value and then added to the depth value of each fragment generated when a polygon is rasterized. The initial value is 0. See $(REF polygonOffset).
	
	- `POLYGON_OFFSET_FILL`: $(I `data`) returns a single boolean value indicating whether polygon offset is enabled for polygons in fill mode. The initial value is `FALSE`. See $(REF polygonOffset).
	
	- `POLYGON_OFFSET_LINE`: $(I `data`) returns a single boolean value indicating whether polygon offset is enabled for polygons in line mode. The initial value is `FALSE`. See $(REF polygonOffset).
	
	- `POLYGON_OFFSET_POINT`: $(I `data`) returns a single boolean value indicating whether polygon offset is enabled for polygons in point mode. The initial value is `FALSE`. See $(REF polygonOffset).
	
	- `POLYGON_SMOOTH`: $(I `data`) returns a single boolean value indicating whether antialiasing of polygons is enabled. The initial value is `FALSE`. See $(REF polygonMode).
	
	- `POLYGON_SMOOTH_HINT`: $(I `data`) returns one value, a symbolic constant indicating the mode of the polygon antialiasing hint. The initial value is `DONT_CARE`. See $(REF hint).
	
	- `READ_BUFFER`: $(I `data`) returns one value, a symbolic constant indicating which color buffer is selected for reading. The initial value is `BACK` if there is a back buffer, otherwise it is `FRONT`. See $(REF readPixels).
	
	- `RENDERBUFFER_BINDING`: $(I `data`) returns a single value, the name of the renderbuffer object currently bound to the target `RENDERBUFFER`. If no renderbuffer object is bound to this target, 0 is returned. The initial value is 0. See $(REF bindRenderbuffer).
	
	- `SAMPLE_BUFFERS`: $(I `data`) returns a single integer value indicating the number of sample buffers associated with the framebuffer. See $(REF sampleCoverage).
	
	- `SAMPLE_COVERAGE_VALUE`: $(I `data`) returns a single positive floating-point value indicating the current sample coverage value. See $(REF sampleCoverage).
	
	- `SAMPLE_COVERAGE_INVERT`: $(I `data`) returns a single boolean value indicating if the temporary coverage value should be inverted. See $(REF sampleCoverage).
	
	- `SAMPLER_BINDING`: $(I `data`) returns a single value, the name of the sampler object currently bound to the active texture unit. The initial value is 0. See $(REF bindSampler).
	
	- `SAMPLES`: $(I `data`) returns a single integer value indicating the coverage mask size. See $(REF sampleCoverage).
	
	- `SCISSOR_BOX`: $(I `data`) returns four values: the x and y window coordinates of the scissor box, followed by its width and height. Initially the x and y window coordinates are both 0 and the width and height are set to the size of the window. See $(REF scissor).
	
	- `SCISSOR_TEST`: $(I `data`) returns a single boolean value indicating whether scissoring is enabled. The initial value is `FALSE`. See $(REF scissor).
	
	- `SHADER_COMPILER`: $(I `data`) returns a single boolean value indicating whether an online shader compiler is present in the implementation. All desktop OpenGL implementations must support online shader compilations, and therefore the value of `SHADER_COMPILER` will always be `TRUE`.
	
	- `SHADER_STORAGE_BUFFER_BINDING`: When used with non-indexed variants of $(REF get) (such as $(REF getIntegerv)), $(I `data`) returns a single value, the name of the buffer object currently bound to the target `SHADER_STORAGE_BUFFER`. If no buffer object is bound to this target, 0 is returned. When used with indexed variants of $(REF get) (such as $(REF getIntegeri_v)), $(I `data`) returns a single value, the name of the buffer object bound to the indexed shader storage buffer binding points. The initial value is 0 for all targets. See $(REF bindBuffer), $(REF bindBufferBase), and $(REF bindBufferRange).
	
	- `SHADER_STORAGE_BUFFER_OFFSET_ALIGNMENT`: $(I `data`) returns a single value, the minimum required alignment for shader storage buffer sizes and offset. The initial value is 1. See $(REF shaderStorageBlockBinding).
	
	- `SHADER_STORAGE_BUFFER_START`: When used with indexed variants of $(REF get) (such as $(REF getInteger64i_v)), $(I `data`) returns a single value, the start offset of the binding range for each indexed shader storage buffer binding. The initial value is 0 for all bindings. See $(REF bindBufferRange).
	
	- `SHADER_STORAGE_BUFFER_SIZE`: When used with indexed variants of $(REF get) (such as $(REF getInteger64i_v)), $(I `data`) returns a single value, the size of the binding range for each indexed shader storage buffer binding. The initial value is 0 for all bindings. See $(REF bindBufferRange).
	
	- `SMOOTH_LINE_WIDTH_RANGE`: $(I `data`) returns a pair of values indicating the range of widths supported for smooth (antialiased) lines. See $(REF lineWidth).
	
	- `SMOOTH_LINE_WIDTH_GRANULARITY`: $(I `data`) returns a single value indicating the level of quantization applied to smooth line width parameters.
	
	- `STENCIL_BACK_FAIL`: $(I `data`) returns one value, a symbolic constant indicating what action is taken for back-facing polygons when the stencil test fails. The initial value is `KEEP`. See $(REF stencilOpSeparate).
	
	- `STENCIL_BACK_FUNC`: $(I `data`) returns one value, a symbolic constant indicating what function is used for back-facing polygons to compare the stencil reference value with the stencil buffer value. The initial value is `ALWAYS`. See $(REF stencilFuncSeparate).
	
	- `STENCIL_BACK_PASS_DEPTH_FAIL`: $(I `data`) returns one value, a symbolic constant indicating what action is taken for back-facing polygons when the stencil test passes, but the depth test fails. The initial value is `KEEP`. See $(REF stencilOpSeparate).
	
	- `STENCIL_BACK_PASS_DEPTH_PASS`: $(I `data`) returns one value, a symbolic constant indicating what action is taken for back-facing polygons when the stencil test passes and the depth test passes. The initial value is `KEEP`. See $(REF stencilOpSeparate).
	
	- `STENCIL_BACK_REF`: $(I `data`) returns one value, the reference value that is compared with the contents of the stencil buffer for back-facing polygons. The initial value is 0. See $(REF stencilFuncSeparate).
	
	- `STENCIL_BACK_VALUE_MASK`: $(I `data`) returns one value, the mask that is used for back-facing polygons to mask both the stencil reference value and the stencil buffer value before they are compared. The initial value is all 1's. See $(REF stencilFuncSeparate).
	
	- `STENCIL_BACK_WRITEMASK`: $(I `data`) returns one value, the mask that controls writing of the stencil bitplanes for back-facing polygons. The initial value is all 1's. See $(REF stencilMaskSeparate).
	
	- `STENCIL_CLEAR_VALUE`: $(I `data`) returns one value, the index to which the stencil bitplanes are cleared. The initial value is 0. See $(REF clearStencil).
	
	- `STENCIL_FAIL`: $(I `data`) returns one value, a symbolic constant indicating what action is taken when the stencil test fails. The initial value is `KEEP`. See $(REF stencilOp). This stencil state only affects non-polygons and front-facing polygons. Back-facing polygons use separate stencil state. See $(REF stencilOpSeparate).
	
	- `STENCIL_FUNC`: $(I `data`) returns one value, a symbolic constant indicating what function is used to compare the stencil reference value with the stencil buffer value. The initial value is `ALWAYS`. See $(REF stencilFunc). This stencil state only affects non-polygons and front-facing polygons. Back-facing polygons use separate stencil state. See $(REF stencilFuncSeparate).
	
	- `STENCIL_PASS_DEPTH_FAIL`: $(I `data`) returns one value, a symbolic constant indicating what action is taken when the stencil test passes, but the depth test fails. The initial value is `KEEP`. See $(REF stencilOp). This stencil state only affects non-polygons and front-facing polygons. Back-facing polygons use separate stencil state. See $(REF stencilOpSeparate).
	
	- `STENCIL_PASS_DEPTH_PASS`: $(I `data`) returns one value, a symbolic constant indicating what action is taken when the stencil test passes and the depth test passes. The initial value is `KEEP`. See $(REF stencilOp). This stencil state only affects non-polygons and front-facing polygons. Back-facing polygons use separate stencil state. See $(REF stencilOpSeparate).
	
	- `STENCIL_REF`: $(I `data`) returns one value, the reference value that is compared with the contents of the stencil buffer. The initial value is 0. See $(REF stencilFunc). This stencil state only affects non-polygons and front-facing polygons. Back-facing polygons use separate stencil state. See $(REF stencilFuncSeparate).
	
	- `STENCIL_TEST`: $(I `data`) returns a single boolean value indicating whether stencil testing of fragments is enabled. The initial value is `FALSE`. See $(REF stencilFunc) and $(REF stencilOp).
	
	- `STENCIL_VALUE_MASK`: $(I `data`) returns one value, the mask that is used to mask both the stencil reference value and the stencil buffer value before they are compared. The initial value is all 1's. See $(REF stencilFunc). This stencil state only affects non-polygons and front-facing polygons. Back-facing polygons use separate stencil state. See $(REF stencilFuncSeparate).
	
	- `STENCIL_WRITEMASK`: $(I `data`) returns one value, the mask that controls writing of the stencil bitplanes. The initial value is all 1's. See $(REF stencilMask). This stencil state only affects non-polygons and front-facing polygons. Back-facing polygons use separate stencil state. See $(REF stencilMaskSeparate).
	
	- `STEREO`: $(I `data`) returns a single boolean value indicating whether stereo buffers (left and right) are supported.
	
	- `SUBPIXEL_BITS`: $(I `data`) returns one value, an estimate of the number of bits of subpixel resolution that are used to position rasterized geometry in window coordinates. The value must be at least 4.
	
	- `TEXTURE_BINDING_1D`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_1D`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_1D_ARRAY`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_1D_ARRAY`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_2D`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_2D`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_2D_ARRAY`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_2D_ARRAY`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_2D_MULTISAMPLE`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_2D_MULTISAMPLE`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_2D_MULTISAMPLE_ARRAY`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_2D_MULTISAMPLE_ARRAY`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_3D`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_3D`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_BUFFER`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_BUFFER`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_CUBE_MAP`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_CUBE_MAP`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_RECTANGLE`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_RECTANGLE`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_COMPRESSION_HINT`: $(I `data`) returns a single value indicating the mode of the texture compression hint. The initial value is `DONT_CARE`.
	
	- `TEXTURE_BINDING_BUFFER`: $(I `data`) returns a single value, the name of the buffer object currently bound to the `TEXTURE_BUFFER` buffer binding point. The initial value is 0. See $(REF bindBuffer).
	
	- `TEXTURE_BUFFER_OFFSET_ALIGNMENT`: $(I `data`) returns a single value, the minimum required alignment for texture buffer sizes and offset. The initial value is 1. See $(REF uniformBlockBinding).
	
	- `TIMESTAMP`: $(I `data`) returns a single value, the 64-bit value of the current GL time. See $(REF queryCounter).
	
	- `TRANSFORM_FEEDBACK_BUFFER_BINDING`: When used with non-indexed variants of $(REF get) (such as $(REF getIntegerv)), $(I `data`) returns a single value, the name of the buffer object currently bound to the target `TRANSFORM_FEEDBACK_BUFFER`. If no buffer object is bound to this target, 0 is returned. When used with indexed variants of $(REF get) (such as $(REF getIntegeri_v)), $(I `data`) returns a single value, the name of the buffer object bound to the indexed transform feedback attribute stream. The initial value is 0 for all targets. See $(REF bindBuffer), $(REF bindBufferBase), and $(REF bindBufferRange).
	
	- `TRANSFORM_FEEDBACK_BUFFER_START`: When used with indexed variants of $(REF get) (such as $(REF getInteger64i_v)), $(I `data`) returns a single value, the start offset of the binding range for each transform feedback attribute stream. The initial value is 0 for all streams. See $(REF bindBufferRange).
	
	- `TRANSFORM_FEEDBACK_BUFFER_SIZE`: When used with indexed variants of $(REF get) (such as $(REF getInteger64i_v)), $(I `data`) returns a single value, the size of the binding range for each transform feedback attribute stream. The initial value is 0 for all streams. See $(REF bindBufferRange).
	
	- `UNIFORM_BUFFER_BINDING`: When used with non-indexed variants of $(REF get) (such as $(REF getIntegerv)), $(I `data`) returns a single value, the name of the buffer object currently bound to the target `UNIFORM_BUFFER`. If no buffer object is bound to this target, 0 is returned. When used with indexed variants of $(REF get) (such as $(REF getIntegeri_v)), $(I `data`) returns a single value, the name of the buffer object bound to the indexed uniform buffer binding point. The initial value is 0 for all targets. See $(REF bindBuffer), $(REF bindBufferBase), and $(REF bindBufferRange).
	
	- `UNIFORM_BUFFER_OFFSET_ALIGNMENT`: $(I `data`) returns a single value, the minimum required alignment for uniform buffer sizes and offset. The initial value is 1. See $(REF uniformBlockBinding).
	
	- `UNIFORM_BUFFER_SIZE`: When used with indexed variants of $(REF get) (such as $(REF getInteger64i_v)), $(I `data`) returns a single value, the size of the binding range for each indexed uniform buffer binding. The initial value is 0 for all bindings. See $(REF bindBufferRange).
	
	- `UNIFORM_BUFFER_START`: When used with indexed variants of $(REF get) (such as $(REF getInteger64i_v)), $(I `data`) returns a single value, the start offset of the binding range for each indexed uniform buffer binding. The initial value is 0 for all bindings. See $(REF bindBufferRange).
	
	- `UNPACK_ALIGNMENT`: $(I `data`) returns one value, the byte alignment used for reading pixel data from memory. The initial value is 4. See $(REF pixelStore).
	
	- `UNPACK_IMAGE_HEIGHT`: $(I `data`) returns one value, the image height used for reading pixel data from memory. The initial is 0. See $(REF pixelStore).
	
	- `UNPACK_LSB_FIRST`: $(I `data`) returns a single boolean value indicating whether single-bit pixels being read from memory are read first from the least significant bit of each unsigned byte. The initial value is `FALSE`. See $(REF pixelStore).
	
	- `UNPACK_ROW_LENGTH`: $(I `data`) returns one value, the row length used for reading pixel data from memory. The initial value is 0. See $(REF pixelStore).
	
	- `UNPACK_SKIP_IMAGES`: $(I `data`) returns one value, the number of pixel images skipped before the first pixel is read from memory. The initial value is 0. See $(REF pixelStore).
	
	- `UNPACK_SKIP_PIXELS`: $(I `data`) returns one value, the number of pixel locations skipped before the first pixel is read from memory. The initial value is 0. See $(REF pixelStore).
	
	- `UNPACK_SKIP_ROWS`: $(I `data`) returns one value, the number of rows of pixel locations skipped before the first pixel is read from memory. The initial value is 0. See $(REF pixelStore).
	
	- `UNPACK_SWAP_BYTES`: $(I `data`) returns a single boolean value indicating whether the bytes of two-byte and four-byte pixel indices and components are swapped after being read from memory. The initial value is `FALSE`. See $(REF pixelStore).
	
	- `VERTEX_ARRAY_BINDING`: $(I `data`) returns a single value, the name of the vertex array object currently bound to the context. If no vertex array object is bound to the context, 0 is returned. The initial value is 0. See $(REF bindVertexArray).
	
	- `VERTEX_BINDING_DIVISOR`: Accepted by the indexed forms. $(I `data`) returns a single integer value representing the instance step divisor of the first element in the bound buffer's data store for vertex attribute bound to $(I `index`).
	
	- `VERTEX_BINDING_OFFSET`: Accepted by the indexed forms. $(I `data`) returns a single integer value representing the byte offset of the first element in the bound buffer's data store for vertex attribute bound to $(I `index`).
	
	- `VERTEX_BINDING_STRIDE`: Accepted by the indexed forms. $(I `data`) returns a single integer value representing the byte offset between the start of each element in the bound buffer's data store for vertex attribute bound to $(I `index`).
	
	- `VERTEX_BINDING_BUFFER`: Accepted by the indexed forms. $(I `data`) returns a single integer value representing the name of the buffer bound to vertex binding $(I `index`).
	
	- `MAX_VERTEX_ATTRIB_RELATIVE_OFFSET`: $(I `data`) returns a single integer value containing the maximum offset that may be added to a vertex binding offset.
	
	- `MAX_VERTEX_ATTRIB_BINDINGS`: $(I `data`) returns a single integer value containing the maximum number of vertex buffers that may be bound.
	
	- `VIEWPORT`: When used with non-indexed variants of $(REF get) (such as $(REF getIntegerv)), $(I `data`) returns four values: the x and y window coordinates of the viewport, followed by its width and height. Initially the x and y window coordinates are both set to 0, and the width and height are set to the width and height of the window into which the GL will do its rendering. See $(REF viewport).   When used with indexed variants of $(REF get) (such as $(REF getIntegeri_v)), $(I `data`) returns four values: the x and y window coordinates of the indexed viewport, followed by its width and height. Initially the x and y window coordinates are both set to 0, and the width and height are set to the width and height of the window into which the GL will do its rendering. See $(REF viewportIndexedf).
	
	- `VIEWPORT_BOUNDS_RANGE`: $(I `data`) returns two values, the minimum and maximum viewport bounds range. The minimum range should be at least [-32768, 32767].
	
	- `VIEWPORT_INDEX_PROVOKING_VERTEX`: $(I `data`) returns one value, the implementation dependent specifc vertex of a primitive that is used to select the viewport index. If the value returned is equivalent to `PROVOKING_VERTEX`, then the vertex selection follows the convention specified by $(REF provokingVertex). If the value returned is equivalent to `FIRST_VERTEX_CONVENTION`, then the selection is always taken from the first vertex in the primitive. If the value returned is equivalent to `LAST_VERTEX_CONVENTION`, then the selection is always taken from the last vertex in the primitive. If the value returned is equivalent to `UNDEFINED_VERTEX`, then the selection is not guaranteed to be taken from any specific vertex in the primitive.
	
	- `VIEWPORT_SUBPIXEL_BITS`: $(I `data`) returns a single value, the number of bits of sub-pixel precision which the GL uses to interpret the floating point viewport bounds. The minimum value is 0.
	
	- `MAX_ELEMENT_INDEX`: $(I `data`) returns a single value, the maximum index that may be specified during the transfer of generic vertex attributes to the GL.
	
	Many of the boolean parameters can also be queried more easily using $(REF isEnabled).
	
	Params:
	pname = Specifies the parameter value to be returned for non-indexed versions of $(REF get). The symbolic constants in the list below are accepted.
	data = Returns the value or values of the specified parameter.
	*/
	void getBooleanv(Enum pname, Boolean* data);
	
	/**
	These commands return values for simple state variables in GL. $(I `pname`) is a symbolic constant indicating the state variable to be returned, and $(I `data`) is a pointer to an array of the indicated type in which to place the returned data.
	
	Type conversion is performed if $(I `data`) has a different type than the state variable value being requested. If $(REF getBooleanv) is called, a floating-point (or integer) value is converted to `FALSE` if and only if it is 0.0 (or 0). Otherwise, it is converted to `TRUE`. If $(REF getIntegerv) is called, boolean values are returned as `TRUE` or `FALSE`, and most floating-point values are rounded to the nearest integer value. Floating-point colors and normals, however, are returned with a linear mapping that maps 1.0 to the most positive representable integer value and -1.0 to the most negative representable integer value. If $(REF getFloatv) or $(REF getDoublev) is called, boolean values are returned as `TRUE` or `FALSE`, and integer values are converted to floating-point values.
	
	The following symbolic constants are accepted by $(I `pname`):
	
	- `ACTIVE_TEXTURE`: $(I `data`) returns a single value indicating the active multitexture unit. The initial value is `TEXTURE0`. See $(REF activeTexture).
	
	- `ALIASED_LINE_WIDTH_RANGE`: $(I `data`) returns a pair of values indicating the range of widths supported for aliased lines. See $(REF lineWidth).
	
	- `ARRAY_BUFFER_BINDING`: $(I `data`) returns a single value, the name of the buffer object currently bound to the target `ARRAY_BUFFER`. If no buffer object is bound to this target, 0 is returned. The initial value is 0. See $(REF bindBuffer).
	
	- `BLEND`: $(I `data`) returns a single boolean value indicating whether blending is enabled. The initial value is `FALSE`. See $(REF blendFunc).
	
	- `BLEND_COLOR`: $(I `data`) returns four values, the red, green, blue, and alpha values which are the components of the blend color. See $(REF blendColor).
	
	- `BLEND_DST_ALPHA`: $(I `data`) returns one value, the symbolic constant identifying the alpha destination blend function. The initial value is `ZERO`. See $(REF blendFunc) and $(REF blendFuncSeparate).
	
	- `BLEND_DST_RGB`: $(I `data`) returns one value, the symbolic constant identifying the RGB destination blend function. The initial value is `ZERO`. See $(REF blendFunc) and $(REF blendFuncSeparate).
	
	- `BLEND_EQUATION_RGB`: $(I `data`) returns one value, a symbolic constant indicating whether the RGB blend equation is `FUNC_ADD`, `FUNC_SUBTRACT`, `FUNC_REVERSE_SUBTRACT`, `MIN` or `MAX`. See $(REF blendEquationSeparate).
	
	- `BLEND_EQUATION_ALPHA`: $(I `data`) returns one value, a symbolic constant indicating whether the Alpha blend equation is `FUNC_ADD`, `FUNC_SUBTRACT`, `FUNC_REVERSE_SUBTRACT`, `MIN` or `MAX`. See $(REF blendEquationSeparate).
	
	- `BLEND_SRC_ALPHA`: $(I `data`) returns one value, the symbolic constant identifying the alpha source blend function. The initial value is `ONE`. See $(REF blendFunc) and $(REF blendFuncSeparate).
	
	- `BLEND_SRC_RGB`: $(I `data`) returns one value, the symbolic constant identifying the RGB source blend function. The initial value is `ONE`. See $(REF blendFunc) and $(REF blendFuncSeparate).
	
	- `COLOR_CLEAR_VALUE`: $(I `data`) returns four values: the red, green, blue, and alpha values used to clear the color buffers. Integer values, if requested, are linearly mapped from the internal floating-point representation such that 1.0 returns the most positive representable integer value, and  -1.0  returns the most negative representable integer value. The initial value is (0, 0, 0, 0). See $(REF clearColor).
	
	- `COLOR_LOGIC_OP`: $(I `data`) returns a single boolean value indicating whether a fragment's RGBA color values are merged into the framebuffer using a logical operation. The initial value is `FALSE`. See $(REF logicOp).
	
	- `COLOR_WRITEMASK`: $(I `data`) returns four boolean values: the red, green, blue, and alpha write enables for the color buffers. The initial value is (`TRUE`, `TRUE`, `TRUE`, `TRUE`). See $(REF colorMask).
	
	- `COMPRESSED_TEXTURE_FORMATS`: $(I `data`) returns a list of symbolic constants of length `NUM_COMPRESSED_TEXTURE_FORMATS` indicating which compressed texture formats are available. See $(REF compressedTexImage2D).
	
	- `MAX_COMPUTE_SHADER_STORAGE_BLOCKS`: $(I `data`) returns one value, the maximum number of active shader storage blocks that may be accessed by a compute shader.
	
	- `MAX_COMBINED_SHADER_STORAGE_BLOCKS`: $(I `data`) returns one value, the maximum total number of active shader storage blocks that may be accessed by all active shaders.
	
	- `MAX_COMPUTE_UNIFORM_BLOCKS`: $(I `data`) returns one value, the maximum number of uniform blocks per compute shader. The value must be at least 14. See $(REF uniformBlockBinding).
	
	- `MAX_COMPUTE_TEXTURE_IMAGE_UNITS`: $(I `data`) returns one value, the maximum supported texture image units that can be used to access texture maps from the compute shader. The value may be at least 16. See $(REF activeTexture).
	
	- `MAX_COMPUTE_UNIFORM_COMPONENTS`: $(I `data`) returns one value, the maximum number of individual floating-point, integer, or boolean values that can be held in uniform variable storage for a compute shader. The value must be at least 1024. See $(REF uniform).
	
	- `MAX_COMPUTE_ATOMIC_COUNTERS`: $(I `data`) returns a single value, the maximum number of atomic counters available to compute shaders.
	
	- `MAX_COMPUTE_ATOMIC_COUNTER_BUFFERS`: $(I `data`) returns a single value, the maximum number of atomic counter buffers that may be accessed by a compute shader.
	
	- `MAX_COMBINED_COMPUTE_UNIFORM_COMPONENTS`: $(I `data`) returns one value, the number of words for compute shader uniform variables in all uniform blocks (including default). The value must be at least 1. See $(REF uniform).
	
	- `MAX_COMPUTE_WORK_GROUP_INVOCATIONS`: $(I `data`) returns one value, the number of invocations in a single local work group (i.e., the product of the three dimensions) that may be dispatched to a compute shader.
	
	- `MAX_COMPUTE_WORK_GROUP_COUNT`: Accepted by the indexed versions of $(REF get). $(I `data`) the maximum number of work groups that may be dispatched to a compute shader. Indices 0, 1, and 2 correspond to the X, Y and Z dimensions, respectively.
	
	- `MAX_COMPUTE_WORK_GROUP_SIZE`: Accepted by the indexed versions of $(REF get). $(I `data`) the maximum size of a work groups that may be used during compilation of a compute shader. Indices 0, 1, and 2 correspond to the X, Y and Z dimensions, respectively.
	
	- `DISPATCH_INDIRECT_BUFFER_BINDING`: $(I `data`) returns a single value, the name of the buffer object currently bound to the target `DISPATCH_INDIRECT_BUFFER`. If no buffer object is bound to this target, 0 is returned. The initial value is 0. See $(REF bindBuffer).
	
	- `MAX_DEBUG_GROUP_STACK_DEPTH`: $(I `data`) returns a single value, the maximum depth of the debug message group stack.
	
	- `DEBUG_GROUP_STACK_DEPTH`: $(I `data`) returns a single value, the current depth of the debug message group stack.
	
	- `CONTEXT_FLAGS`: $(I `data`) returns one value, the flags with which the context was created (such as debugging functionality).
	
	- `CULL_FACE`: $(I `data`) returns a single boolean value indicating whether polygon culling is enabled. The initial value is `FALSE`. See $(REF cullFace).
	
	- `CULL_FACE_MODE`: $(I `data`) returns a single value indicating the mode of polygon culling. The initial value is `BACK`. See $(REF cullFace).
	
	- `CURRENT_PROGRAM`: $(I `data`) returns one value, the name of the program object that is currently active, or 0 if no program object is active. See $(REF useProgram).
	
	- `DEPTH_CLEAR_VALUE`: $(I `data`) returns one value, the value that is used to clear the depth buffer. Integer values, if requested, are linearly mapped from the internal floating-point representation such that 1.0 returns the most positive representable integer value, and  -1.0  returns the most negative representable integer value. The initial value is 1. See $(REF clearDepth).
	
	- `DEPTH_FUNC`: $(I `data`) returns one value, the symbolic constant that indicates the depth comparison function. The initial value is `LESS`. See $(REF depthFunc).
	
	- `DEPTH_RANGE`: $(I `data`) returns two values: the near and far mapping limits for the depth buffer. Integer values, if requested, are linearly mapped from the internal floating-point representation such that 1.0 returns the most positive representable integer value, and  -1.0  returns the most negative representable integer value. The initial value is (0, 1). See $(REF depthRange).
	
	- `DEPTH_TEST`: $(I `data`) returns a single boolean value indicating whether depth testing of fragments is enabled. The initial value is `FALSE`. See $(REF depthFunc) and $(REF depthRange).
	
	- `DEPTH_WRITEMASK`: $(I `data`) returns a single boolean value indicating if the depth buffer is enabled for writing. The initial value is `TRUE`. See $(REF depthMask).
	
	- `DITHER`: $(I `data`) returns a single boolean value indicating whether dithering of fragment colors and indices is enabled. The initial value is `TRUE`.
	
	- `DOUBLEBUFFER`: $(I `data`) returns a single boolean value indicating whether double buffering is supported.
	
	- `DRAW_BUFFER`: $(I `data`) returns one value, a symbolic constant indicating which buffers are being drawn to. See $(REF drawBuffer). The initial value is `BACK` if there are back buffers, otherwise it is `FRONT`.
	
	- `DRAW_BUFFER`  $(I i): $(I `data`) returns one value, a symbolic constant indicating which buffers are being drawn to by the corresponding output color. See $(REF drawBuffers). The initial value of `DRAW_BUFFER0` is `BACK` if there are back buffers, otherwise it is `FRONT`. The initial values of draw buffers for all other output colors is `NONE`.
	
	- `DRAW_FRAMEBUFFER_BINDING`: $(I `data`) returns one value, the name of the framebuffer object currently bound to the `DRAW_FRAMEBUFFER` target. If the default framebuffer is bound, this value will be zero. The initial value is zero. See $(REF bindFramebuffer).
	
	- `READ_FRAMEBUFFER_BINDING`: $(I `data`) returns one value, the name of the framebuffer object currently bound to the `READ_FRAMEBUFFER` target. If the default framebuffer is bound, this value will be zero. The initial value is zero. See $(REF bindFramebuffer).
	
	- `ELEMENT_ARRAY_BUFFER_BINDING`: $(I `data`) returns a single value, the name of the buffer object currently bound to the target `ELEMENT_ARRAY_BUFFER`. If no buffer object is bound to this target, 0 is returned. The initial value is 0. See $(REF bindBuffer).
	
	- `FRAGMENT_SHADER_DERIVATIVE_HINT`: $(I `data`) returns one value, a symbolic constant indicating the mode of the derivative accuracy hint for fragment shaders. The initial value is `DONT_CARE`. See $(REF hint).
	
	- `IMPLEMENTATION_COLOR_READ_FORMAT`: $(I `data`) returns a single GLenum value indicating the implementation's preferred pixel data format. See $(REF readPixels).
	
	- `IMPLEMENTATION_COLOR_READ_TYPE`: $(I `data`) returns a single GLenum value indicating the implementation's preferred pixel data type. See $(REF readPixels).
	
	- `LINE_SMOOTH`: $(I `data`) returns a single boolean value indicating whether antialiasing of lines is enabled. The initial value is `FALSE`. See $(REF lineWidth).
	
	- `LINE_SMOOTH_HINT`: $(I `data`) returns one value, a symbolic constant indicating the mode of the line antialiasing hint. The initial value is `DONT_CARE`. See $(REF hint).
	
	- `LINE_WIDTH`: $(I `data`) returns one value, the line width as specified with $(REF lineWidth). The initial value is 1.
	
	- `LAYER_PROVOKING_VERTEX`: $(I `data`) returns one value, the implementation dependent specifc vertex of a primitive that is used to select the rendering layer. If the value returned is equivalent to `PROVOKING_VERTEX`, then the vertex selection follows the convention specified by $(REF provokingVertex). If the value returned is equivalent to `FIRST_VERTEX_CONVENTION`, then the selection is always taken from the first vertex in the primitive. If the value returned is equivalent to `LAST_VERTEX_CONVENTION`, then the selection is always taken from the last vertex in the primitive. If the value returned is equivalent to `UNDEFINED_VERTEX`, then the selection is not guaranteed to be taken from any specific vertex in the primitive.
	
	- `LOGIC_OP_MODE`: $(I `data`) returns one value, a symbolic constant indicating the selected logic operation mode. The initial value is `COPY`. See $(REF logicOp).
	
	- `MAJOR_VERSION`: $(I `data`) returns one value, the major version number of the OpenGL API supported by the current context.
	
	- `MAX_3D_TEXTURE_SIZE`: $(I `data`) returns one value, a rough estimate of the largest 3D texture that the GL can handle. The value must be at least 64. Use `PROXY_TEXTURE_3D` to determine if a texture is too large. See $(REF texImage3D).
	
	- `MAX_ARRAY_TEXTURE_LAYERS`: $(I `data`) returns one value. The value indicates the maximum number of layers allowed in an array texture, and must be at least 256. See $(REF texImage2D).
	
	- `MAX_CLIP_DISTANCES`: $(I `data`) returns one value, the maximum number of application-defined clipping distances. The value must be at least 8.
	
	- `MAX_COLOR_TEXTURE_SAMPLES`: $(I `data`) returns one value, the maximum number of samples in a color multisample texture.
	
	- `MAX_COMBINED_ATOMIC_COUNTERS`: $(I `data`) returns a single value, the maximum number of atomic counters available to all active shaders.
	
	- `MAX_COMBINED_FRAGMENT_UNIFORM_COMPONENTS`: $(I `data`) returns one value, the number of words for fragment shader uniform variables in all uniform blocks (including default). The value must be at least 1. See $(REF uniform).
	
	- `MAX_COMBINED_GEOMETRY_UNIFORM_COMPONENTS`: $(I `data`) returns one value, the number of words for geometry shader uniform variables in all uniform blocks (including default). The value must be at least 1. See $(REF uniform).
	
	- `MAX_COMBINED_TEXTURE_IMAGE_UNITS`: $(I `data`) returns one value, the maximum supported texture image units that can be used to access texture maps from the vertex shader and the fragment processor combined. If both the vertex shader and the fragment processing stage access the same texture image unit, then that counts as using two texture image units against this limit. The value must be at least 48. See $(REF activeTexture).
	
	- `MAX_COMBINED_UNIFORM_BLOCKS`: $(I `data`) returns one value, the maximum number of uniform blocks per program. The value must be at least 70. See $(REF uniformBlockBinding).
	
	- `MAX_COMBINED_VERTEX_UNIFORM_COMPONENTS`: $(I `data`) returns one value, the number of words for vertex shader uniform variables in all uniform blocks (including default). The value must be at least 1. See $(REF uniform).
	
	- `MAX_CUBE_MAP_TEXTURE_SIZE`: $(I `data`) returns one value. The value gives a rough estimate of the largest cube-map texture that the GL can handle. The value must be at least 1024. Use `PROXY_TEXTURE_CUBE_MAP` to determine if a texture is too large. See $(REF texImage2D).
	
	- `MAX_DEPTH_TEXTURE_SAMPLES`: $(I `data`) returns one value, the maximum number of samples in a multisample depth or depth-stencil texture.
	
	- `MAX_DRAW_BUFFERS`: $(I `data`) returns one value, the maximum number of simultaneous outputs that may be written in a fragment shader. The value must be at least 8. See $(REF drawBuffers).
	
	- `MAX_DUAL_SOURCE_DRAW_BUFFERS`: $(I `data`) returns one value, the maximum number of active draw buffers when using dual-source blending. The value must be at least 1. See $(REF blendFunc) and $(REF blendFuncSeparate).
	
	- `MAX_ELEMENTS_INDICES`: $(I `data`) returns one value, the recommended maximum number of vertex array indices. See $(REF drawRangeElements).
	
	- `MAX_ELEMENTS_VERTICES`: $(I `data`) returns one value, the recommended maximum number of vertex array vertices. See $(REF drawRangeElements).
	
	- `MAX_FRAGMENT_ATOMIC_COUNTERS`: $(I `data`) returns a single value, the maximum number of atomic counters available to fragment shaders.
	
	- `MAX_FRAGMENT_SHADER_STORAGE_BLOCKS`: $(I `data`) returns one value, the maximum number of active shader storage blocks that may be accessed by a fragment shader.
	
	- `MAX_FRAGMENT_INPUT_COMPONENTS`: $(I `data`) returns one value, the maximum number of components of the inputs read by the fragment shader, which must be at least 128.
	
	- `MAX_FRAGMENT_UNIFORM_COMPONENTS`: $(I `data`) returns one value, the maximum number of individual floating-point, integer, or boolean values that can be held in uniform variable storage for a fragment shader. The value must be at least 1024. See $(REF uniform).
	
	- `MAX_FRAGMENT_UNIFORM_VECTORS`: $(I `data`) returns one value, the maximum number of individual 4-vectors of floating-point, integer, or boolean values that can be held in uniform variable storage for a fragment shader. The value is equal to the value of `MAX_FRAGMENT_UNIFORM_COMPONENTS` divided by 4 and must be at least 256. See $(REF uniform).
	
	- `MAX_FRAGMENT_UNIFORM_BLOCKS`: $(I `data`) returns one value, the maximum number of uniform blocks per fragment shader. The value must be at least 12. See $(REF uniformBlockBinding).
	
	- `MAX_FRAMEBUFFER_WIDTH`: $(I `data`) returns one value, the maximum width for a framebuffer that has no attachments, which must be at least 16384. See $(REF framebufferParameter).
	
	- `MAX_FRAMEBUFFER_HEIGHT`: $(I `data`) returns one value, the maximum height for a framebuffer that has no attachments, which must be at least 16384. See $(REF framebufferParameter).
	
	- `MAX_FRAMEBUFFER_LAYERS`: $(I `data`) returns one value, the maximum number of layers for a framebuffer that has no attachments, which must be at least 2048. See $(REF framebufferParameter).
	
	- `MAX_FRAMEBUFFER_SAMPLES`: $(I `data`) returns one value, the maximum samples in a framebuffer that has no attachments, which must be at least 4. See $(REF framebufferParameter).
	
	- `MAX_GEOMETRY_ATOMIC_COUNTERS`: $(I `data`) returns a single value, the maximum number of atomic counters available to geometry shaders.
	
	- `MAX_GEOMETRY_SHADER_STORAGE_BLOCKS`: $(I `data`) returns one value, the maximum number of active shader storage blocks that may be accessed by a geometry shader.
	
	- `MAX_GEOMETRY_INPUT_COMPONENTS`: $(I `data`) returns one value, the maximum number of components of inputs read by a geometry shader, which must be at least 64.
	
	- `MAX_GEOMETRY_OUTPUT_COMPONENTS`: $(I `data`) returns one value, the maximum number of components of outputs written by a geometry shader, which must be at least 128.
	
	- `MAX_GEOMETRY_TEXTURE_IMAGE_UNITS`: $(I `data`) returns one value, the maximum supported texture image units that can be used to access texture maps from the geometry shader. The value must be at least 16. See $(REF activeTexture).
	
	- `MAX_GEOMETRY_UNIFORM_BLOCKS`: $(I `data`) returns one value, the maximum number of uniform blocks per geometry shader. The value must be at least 12. See $(REF uniformBlockBinding).
	
	- `MAX_GEOMETRY_UNIFORM_COMPONENTS`: $(I `data`) returns one value, the maximum number of individual floating-point, integer, or boolean values that can be held in uniform variable storage for a geometry shader. The value must be at least 1024. See $(REF uniform).
	
	- `MAX_INTEGER_SAMPLES`: $(I `data`) returns one value, the maximum number of samples supported in integer format multisample buffers.
	
	- `MIN_MAP_BUFFER_ALIGNMENT`: $(I `data`) returns one value, the minimum alignment in basic machine units of pointers returned from$(REF mapBuffer) and $(REF mapBufferRange). This value must be a power of two and must be at least 64.
	
	- `MAX_LABEL_LENGTH`: $(I `data`) returns one value, the maximum length of a label that may be assigned to an object. See $(REF objectLabel) and $(REF objectPtrLabel).
	
	- `MAX_PROGRAM_TEXEL_OFFSET`: $(I `data`) returns one value, the maximum texel offset allowed in a texture lookup, which must be at least 7.
	
	- `MIN_PROGRAM_TEXEL_OFFSET`: $(I `data`) returns one value, the minimum texel offset allowed in a texture lookup, which must be at most -8.
	
	- `MAX_RECTANGLE_TEXTURE_SIZE`: $(I `data`) returns one value. The value gives a rough estimate of the largest rectangular texture that the GL can handle. The value must be at least 1024. Use `PROXY_TEXTURE_RECTANGLE` to determine if a texture is too large. See $(REF texImage2D).
	
	- `MAX_RENDERBUFFER_SIZE`: $(I `data`) returns one value. The value indicates the maximum supported size for renderbuffers. See $(REF framebufferRenderbuffer).
	
	- `MAX_SAMPLE_MASK_WORDS`: $(I `data`) returns one value, the maximum number of sample mask words.
	
	- `MAX_SERVER_WAIT_TIMEOUT`: $(I `data`) returns one value, the maximum $(REF waitSync) timeout interval.
	
	- `MAX_SHADER_STORAGE_BUFFER_BINDINGS`: $(I `data`) returns one value, the maximum number of shader storage buffer binding points on the context, which must be at least 8.
	
	- `MAX_TESS_CONTROL_ATOMIC_COUNTERS`: $(I `data`) returns a single value, the maximum number of atomic counters available to tessellation control shaders.
	
	- `MAX_TESS_EVALUATION_ATOMIC_COUNTERS`: $(I `data`) returns a single value, the maximum number of atomic counters available to tessellation evaluation shaders.
	
	- `MAX_TESS_CONTROL_SHADER_STORAGE_BLOCKS`: $(I `data`) returns one value, the maximum number of active shader storage blocks that may be accessed by a tessellation control shader.
	
	- `MAX_TESS_EVALUATION_SHADER_STORAGE_BLOCKS`: $(I `data`) returns one value, the maximum number of active shader storage blocks that may be accessed by a tessellation evaluation shader.
	
	- `MAX_TEXTURE_BUFFER_SIZE`: $(I `data`) returns one value. The value gives the maximum number of texels allowed in the texel array of a texture buffer object. Value must be at least 65536.
	
	- `MAX_TEXTURE_IMAGE_UNITS`: $(I `data`) returns one value, the maximum supported texture image units that can be used to access texture maps from the fragment shader. The value must be at least 16. See $(REF activeTexture).
	
	- `MAX_TEXTURE_LOD_BIAS`: $(I `data`) returns one value, the maximum, absolute value of the texture level-of-detail bias. The value must be at least 2.0.
	
	- `MAX_TEXTURE_SIZE`: $(I `data`) returns one value. The value gives a rough estimate of the largest texture that the GL can handle. The value must be at least 1024. Use a proxy texture target such as `PROXY_TEXTURE_1D` or `PROXY_TEXTURE_2D` to determine if a texture is too large. See $(REF texImage1D) and $(REF texImage2D).
	
	- `MAX_UNIFORM_BUFFER_BINDINGS`: $(I `data`) returns one value, the maximum number of uniform buffer binding points on the context, which must be at least 36.
	
	- `MAX_UNIFORM_BLOCK_SIZE`: $(I `data`) returns one value, the maximum size in basic machine units of a uniform block, which must be at least 16384.
	
	- `MAX_UNIFORM_LOCATIONS`: $(I `data`) returns one value, the maximum number of explicitly assignable uniform locations, which must be at least 1024.
	
	- `MAX_VARYING_COMPONENTS`: $(I `data`) returns one value, the number components for varying variables, which must be at least 60.
	
	- `MAX_VARYING_VECTORS`: $(I `data`) returns one value, the number 4-vectors for varying variables, which is equal to the value of `MAX_VARYING_COMPONENTS` and must be at least 15.
	
	- `MAX_VARYING_FLOATS`: $(I `data`) returns one value, the maximum number of interpolators available for processing varying variables used by vertex and fragment shaders. This value represents the number of individual floating-point values that can be interpolated; varying variables declared as vectors, matrices, and arrays will all consume multiple interpolators. The value must be at least 32.
	
	- `MAX_VERTEX_ATOMIC_COUNTERS`: $(I `data`) returns a single value, the maximum number of atomic counters available to vertex shaders.
	
	- `MAX_VERTEX_ATTRIBS`: $(I `data`) returns one value, the maximum number of 4-component generic vertex attributes accessible to a vertex shader. The value must be at least 16. See $(REF vertexAttrib).
	
	- `MAX_VERTEX_SHADER_STORAGE_BLOCKS`: $(I `data`) returns one value, the maximum number of active shader storage blocks that may be accessed by a vertex shader.
	
	- `MAX_VERTEX_TEXTURE_IMAGE_UNITS`: $(I `data`) returns one value, the maximum supported texture image units that can be used to access texture maps from the vertex shader. The value may be at least 16. See $(REF activeTexture).
	
	- `MAX_VERTEX_UNIFORM_COMPONENTS`: $(I `data`) returns one value, the maximum number of individual floating-point, integer, or boolean values that can be held in uniform variable storage for a vertex shader. The value must be at least 1024. See $(REF uniform).
	
	- `MAX_VERTEX_UNIFORM_VECTORS`: $(I `data`) returns one value, the maximum number of 4-vectors that may be held in uniform variable storage for the vertex shader. The value of `MAX_VERTEX_UNIFORM_VECTORS` is equal to the value of `MAX_VERTEX_UNIFORM_COMPONENTS` and must be at least 256.
	
	- `MAX_VERTEX_OUTPUT_COMPONENTS`: $(I `data`) returns one value, the maximum number of components of output written by a vertex shader, which must be at least 64.
	
	- `MAX_VERTEX_UNIFORM_BLOCKS`: $(I `data`) returns one value, the maximum number of uniform blocks per vertex shader. The value must be at least 12. See $(REF uniformBlockBinding).
	
	- `MAX_VIEWPORT_DIMS`: $(I `data`) returns two values: the maximum supported width and height of the viewport. These must be at least as large as the visible dimensions of the display being rendered to. See $(REF viewport).
	
	- `MAX_VIEWPORTS`: $(I `data`) returns one value, the maximum number of simultaneous viewports that are supported. The value must be at least 16. See $(REF viewportIndexed).
	
	- `MINOR_VERSION`: $(I `data`) returns one value, the minor version number of the OpenGL API supported by the current context.
	
	- `NUM_COMPRESSED_TEXTURE_FORMATS`: $(I `data`) returns a single integer value indicating the number of available compressed texture formats. The minimum value is 4. See $(REF compressedTexImage2D).
	
	- `NUM_EXTENSIONS`: $(I `data`) returns one value, the number of extensions supported by the GL implementation for the current context. See $(REF getString).
	
	- `NUM_PROGRAM_BINARY_FORMATS`: $(I `data`) returns one value, the number of program binary formats supported by the implementation.
	
	- `NUM_SHADER_BINARY_FORMATS`: $(I `data`) returns one value, the number of binary shader formats supported by the implementation. If this value is greater than zero, then the implementation supports loading binary shaders. If it is zero, then the loading of binary shaders by the implementation is not supported.
	
	- `PACK_ALIGNMENT`: $(I `data`) returns one value, the byte alignment used for writing pixel data to memory. The initial value is 4. See $(REF pixelStore).
	
	- `PACK_IMAGE_HEIGHT`: $(I `data`) returns one value, the image height used for writing pixel data to memory. The initial value is 0. See $(REF pixelStore).
	
	- `PACK_LSB_FIRST`: $(I `data`) returns a single boolean value indicating whether single-bit pixels being written to memory are written first to the least significant bit of each unsigned byte. The initial value is `FALSE`. See $(REF pixelStore).
	
	- `PACK_ROW_LENGTH`: $(I `data`) returns one value, the row length used for writing pixel data to memory. The initial value is 0. See $(REF pixelStore).
	
	- `PACK_SKIP_IMAGES`: $(I `data`) returns one value, the number of pixel images skipped before the first pixel is written into memory. The initial value is 0. See $(REF pixelStore).
	
	- `PACK_SKIP_PIXELS`: $(I `data`) returns one value, the number of pixel locations skipped before the first pixel is written into memory. The initial value is 0. See $(REF pixelStore).
	
	- `PACK_SKIP_ROWS`: $(I `data`) returns one value, the number of rows of pixel locations skipped before the first pixel is written into memory. The initial value is 0. See $(REF pixelStore).
	
	- `PACK_SWAP_BYTES`: $(I `data`) returns a single boolean value indicating whether the bytes of two-byte and four-byte pixel indices and components are swapped before being written to memory. The initial value is `FALSE`. See $(REF pixelStore).
	
	- `PIXEL_PACK_BUFFER_BINDING`: $(I `data`) returns a single value, the name of the buffer object currently bound to the target `PIXEL_PACK_BUFFER`. If no buffer object is bound to this target, 0 is returned. The initial value is 0. See $(REF bindBuffer).
	
	- `PIXEL_UNPACK_BUFFER_BINDING`: $(I `data`) returns a single value, the name of the buffer object currently bound to the target `PIXEL_UNPACK_BUFFER`. If no buffer object is bound to this target, 0 is returned. The initial value is 0. See $(REF bindBuffer).
	
	- `POINT_FADE_THRESHOLD_SIZE`: $(I `data`) returns one value, the point size threshold for determining the point size. See $(REF pointParameter).
	
	- `PRIMITIVE_RESTART_INDEX`: $(I `data`) returns one value, the current primitive restart index. The initial value is 0. See $(REF primitiveRestartIndex).
	
	- `PROGRAM_BINARY_FORMATS`: $(I `data`) an array of `NUM_PROGRAM_BINARY_FORMATS` values, indicating the proram binary formats supported by the implementation.
	
	- `PROGRAM_PIPELINE_BINDING`: $(I `data`) a single value, the name of the currently bound program pipeline object, or zero if no program pipeline object is bound. See $(REF bindProgramPipeline).
	
	- `PROGRAM_POINT_SIZE`: $(I `data`) returns a single boolean value indicating whether vertex program point size mode is enabled. If enabled, then the point size is taken from the shader built-in `gl_PointSize`. If disabled, then the point size is taken from the point state as specified by $(REF pointSize). The initial value is `FALSE`.
	
	- `PROVOKING_VERTEX`: $(I `data`) returns one value, the currently selected provoking vertex convention. The initial value is `LAST_VERTEX_CONVENTION`. See $(REF provokingVertex).
	
	- `POINT_SIZE`: $(I `data`) returns one value, the point size as specified by $(REF pointSize). The initial value is 1.
	
	- `POINT_SIZE_GRANULARITY`: $(I `data`) returns one value, the size difference between adjacent supported sizes for antialiased points. See $(REF pointSize).
	
	- `POINT_SIZE_RANGE`: $(I `data`) returns two values: the smallest and largest supported sizes for antialiased points. The smallest size must be at most 1, and the largest size must be at least 1. See $(REF pointSize).
	
	- `POLYGON_OFFSET_FACTOR`: $(I `data`) returns one value, the scaling factor used to determine the variable offset that is added to the depth value of each fragment generated when a polygon is rasterized. The initial value is 0. See $(REF polygonOffset).
	
	- `POLYGON_OFFSET_UNITS`: $(I `data`) returns one value. This value is multiplied by an implementation-specific value and then added to the depth value of each fragment generated when a polygon is rasterized. The initial value is 0. See $(REF polygonOffset).
	
	- `POLYGON_OFFSET_FILL`: $(I `data`) returns a single boolean value indicating whether polygon offset is enabled for polygons in fill mode. The initial value is `FALSE`. See $(REF polygonOffset).
	
	- `POLYGON_OFFSET_LINE`: $(I `data`) returns a single boolean value indicating whether polygon offset is enabled for polygons in line mode. The initial value is `FALSE`. See $(REF polygonOffset).
	
	- `POLYGON_OFFSET_POINT`: $(I `data`) returns a single boolean value indicating whether polygon offset is enabled for polygons in point mode. The initial value is `FALSE`. See $(REF polygonOffset).
	
	- `POLYGON_SMOOTH`: $(I `data`) returns a single boolean value indicating whether antialiasing of polygons is enabled. The initial value is `FALSE`. See $(REF polygonMode).
	
	- `POLYGON_SMOOTH_HINT`: $(I `data`) returns one value, a symbolic constant indicating the mode of the polygon antialiasing hint. The initial value is `DONT_CARE`. See $(REF hint).
	
	- `READ_BUFFER`: $(I `data`) returns one value, a symbolic constant indicating which color buffer is selected for reading. The initial value is `BACK` if there is a back buffer, otherwise it is `FRONT`. See $(REF readPixels).
	
	- `RENDERBUFFER_BINDING`: $(I `data`) returns a single value, the name of the renderbuffer object currently bound to the target `RENDERBUFFER`. If no renderbuffer object is bound to this target, 0 is returned. The initial value is 0. See $(REF bindRenderbuffer).
	
	- `SAMPLE_BUFFERS`: $(I `data`) returns a single integer value indicating the number of sample buffers associated with the framebuffer. See $(REF sampleCoverage).
	
	- `SAMPLE_COVERAGE_VALUE`: $(I `data`) returns a single positive floating-point value indicating the current sample coverage value. See $(REF sampleCoverage).
	
	- `SAMPLE_COVERAGE_INVERT`: $(I `data`) returns a single boolean value indicating if the temporary coverage value should be inverted. See $(REF sampleCoverage).
	
	- `SAMPLER_BINDING`: $(I `data`) returns a single value, the name of the sampler object currently bound to the active texture unit. The initial value is 0. See $(REF bindSampler).
	
	- `SAMPLES`: $(I `data`) returns a single integer value indicating the coverage mask size. See $(REF sampleCoverage).
	
	- `SCISSOR_BOX`: $(I `data`) returns four values: the x and y window coordinates of the scissor box, followed by its width and height. Initially the x and y window coordinates are both 0 and the width and height are set to the size of the window. See $(REF scissor).
	
	- `SCISSOR_TEST`: $(I `data`) returns a single boolean value indicating whether scissoring is enabled. The initial value is `FALSE`. See $(REF scissor).
	
	- `SHADER_COMPILER`: $(I `data`) returns a single boolean value indicating whether an online shader compiler is present in the implementation. All desktop OpenGL implementations must support online shader compilations, and therefore the value of `SHADER_COMPILER` will always be `TRUE`.
	
	- `SHADER_STORAGE_BUFFER_BINDING`: When used with non-indexed variants of $(REF get) (such as $(REF getIntegerv)), $(I `data`) returns a single value, the name of the buffer object currently bound to the target `SHADER_STORAGE_BUFFER`. If no buffer object is bound to this target, 0 is returned. When used with indexed variants of $(REF get) (such as $(REF getIntegeri_v)), $(I `data`) returns a single value, the name of the buffer object bound to the indexed shader storage buffer binding points. The initial value is 0 for all targets. See $(REF bindBuffer), $(REF bindBufferBase), and $(REF bindBufferRange).
	
	- `SHADER_STORAGE_BUFFER_OFFSET_ALIGNMENT`: $(I `data`) returns a single value, the minimum required alignment for shader storage buffer sizes and offset. The initial value is 1. See $(REF shaderStorageBlockBinding).
	
	- `SHADER_STORAGE_BUFFER_START`: When used with indexed variants of $(REF get) (such as $(REF getInteger64i_v)), $(I `data`) returns a single value, the start offset of the binding range for each indexed shader storage buffer binding. The initial value is 0 for all bindings. See $(REF bindBufferRange).
	
	- `SHADER_STORAGE_BUFFER_SIZE`: When used with indexed variants of $(REF get) (such as $(REF getInteger64i_v)), $(I `data`) returns a single value, the size of the binding range for each indexed shader storage buffer binding. The initial value is 0 for all bindings. See $(REF bindBufferRange).
	
	- `SMOOTH_LINE_WIDTH_RANGE`: $(I `data`) returns a pair of values indicating the range of widths supported for smooth (antialiased) lines. See $(REF lineWidth).
	
	- `SMOOTH_LINE_WIDTH_GRANULARITY`: $(I `data`) returns a single value indicating the level of quantization applied to smooth line width parameters.
	
	- `STENCIL_BACK_FAIL`: $(I `data`) returns one value, a symbolic constant indicating what action is taken for back-facing polygons when the stencil test fails. The initial value is `KEEP`. See $(REF stencilOpSeparate).
	
	- `STENCIL_BACK_FUNC`: $(I `data`) returns one value, a symbolic constant indicating what function is used for back-facing polygons to compare the stencil reference value with the stencil buffer value. The initial value is `ALWAYS`. See $(REF stencilFuncSeparate).
	
	- `STENCIL_BACK_PASS_DEPTH_FAIL`: $(I `data`) returns one value, a symbolic constant indicating what action is taken for back-facing polygons when the stencil test passes, but the depth test fails. The initial value is `KEEP`. See $(REF stencilOpSeparate).
	
	- `STENCIL_BACK_PASS_DEPTH_PASS`: $(I `data`) returns one value, a symbolic constant indicating what action is taken for back-facing polygons when the stencil test passes and the depth test passes. The initial value is `KEEP`. See $(REF stencilOpSeparate).
	
	- `STENCIL_BACK_REF`: $(I `data`) returns one value, the reference value that is compared with the contents of the stencil buffer for back-facing polygons. The initial value is 0. See $(REF stencilFuncSeparate).
	
	- `STENCIL_BACK_VALUE_MASK`: $(I `data`) returns one value, the mask that is used for back-facing polygons to mask both the stencil reference value and the stencil buffer value before they are compared. The initial value is all 1's. See $(REF stencilFuncSeparate).
	
	- `STENCIL_BACK_WRITEMASK`: $(I `data`) returns one value, the mask that controls writing of the stencil bitplanes for back-facing polygons. The initial value is all 1's. See $(REF stencilMaskSeparate).
	
	- `STENCIL_CLEAR_VALUE`: $(I `data`) returns one value, the index to which the stencil bitplanes are cleared. The initial value is 0. See $(REF clearStencil).
	
	- `STENCIL_FAIL`: $(I `data`) returns one value, a symbolic constant indicating what action is taken when the stencil test fails. The initial value is `KEEP`. See $(REF stencilOp). This stencil state only affects non-polygons and front-facing polygons. Back-facing polygons use separate stencil state. See $(REF stencilOpSeparate).
	
	- `STENCIL_FUNC`: $(I `data`) returns one value, a symbolic constant indicating what function is used to compare the stencil reference value with the stencil buffer value. The initial value is `ALWAYS`. See $(REF stencilFunc). This stencil state only affects non-polygons and front-facing polygons. Back-facing polygons use separate stencil state. See $(REF stencilFuncSeparate).
	
	- `STENCIL_PASS_DEPTH_FAIL`: $(I `data`) returns one value, a symbolic constant indicating what action is taken when the stencil test passes, but the depth test fails. The initial value is `KEEP`. See $(REF stencilOp). This stencil state only affects non-polygons and front-facing polygons. Back-facing polygons use separate stencil state. See $(REF stencilOpSeparate).
	
	- `STENCIL_PASS_DEPTH_PASS`: $(I `data`) returns one value, a symbolic constant indicating what action is taken when the stencil test passes and the depth test passes. The initial value is `KEEP`. See $(REF stencilOp). This stencil state only affects non-polygons and front-facing polygons. Back-facing polygons use separate stencil state. See $(REF stencilOpSeparate).
	
	- `STENCIL_REF`: $(I `data`) returns one value, the reference value that is compared with the contents of the stencil buffer. The initial value is 0. See $(REF stencilFunc). This stencil state only affects non-polygons and front-facing polygons. Back-facing polygons use separate stencil state. See $(REF stencilFuncSeparate).
	
	- `STENCIL_TEST`: $(I `data`) returns a single boolean value indicating whether stencil testing of fragments is enabled. The initial value is `FALSE`. See $(REF stencilFunc) and $(REF stencilOp).
	
	- `STENCIL_VALUE_MASK`: $(I `data`) returns one value, the mask that is used to mask both the stencil reference value and the stencil buffer value before they are compared. The initial value is all 1's. See $(REF stencilFunc). This stencil state only affects non-polygons and front-facing polygons. Back-facing polygons use separate stencil state. See $(REF stencilFuncSeparate).
	
	- `STENCIL_WRITEMASK`: $(I `data`) returns one value, the mask that controls writing of the stencil bitplanes. The initial value is all 1's. See $(REF stencilMask). This stencil state only affects non-polygons and front-facing polygons. Back-facing polygons use separate stencil state. See $(REF stencilMaskSeparate).
	
	- `STEREO`: $(I `data`) returns a single boolean value indicating whether stereo buffers (left and right) are supported.
	
	- `SUBPIXEL_BITS`: $(I `data`) returns one value, an estimate of the number of bits of subpixel resolution that are used to position rasterized geometry in window coordinates. The value must be at least 4.
	
	- `TEXTURE_BINDING_1D`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_1D`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_1D_ARRAY`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_1D_ARRAY`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_2D`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_2D`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_2D_ARRAY`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_2D_ARRAY`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_2D_MULTISAMPLE`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_2D_MULTISAMPLE`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_2D_MULTISAMPLE_ARRAY`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_2D_MULTISAMPLE_ARRAY`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_3D`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_3D`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_BUFFER`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_BUFFER`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_CUBE_MAP`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_CUBE_MAP`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_RECTANGLE`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_RECTANGLE`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_COMPRESSION_HINT`: $(I `data`) returns a single value indicating the mode of the texture compression hint. The initial value is `DONT_CARE`.
	
	- `TEXTURE_BINDING_BUFFER`: $(I `data`) returns a single value, the name of the buffer object currently bound to the `TEXTURE_BUFFER` buffer binding point. The initial value is 0. See $(REF bindBuffer).
	
	- `TEXTURE_BUFFER_OFFSET_ALIGNMENT`: $(I `data`) returns a single value, the minimum required alignment for texture buffer sizes and offset. The initial value is 1. See $(REF uniformBlockBinding).
	
	- `TIMESTAMP`: $(I `data`) returns a single value, the 64-bit value of the current GL time. See $(REF queryCounter).
	
	- `TRANSFORM_FEEDBACK_BUFFER_BINDING`: When used with non-indexed variants of $(REF get) (such as $(REF getIntegerv)), $(I `data`) returns a single value, the name of the buffer object currently bound to the target `TRANSFORM_FEEDBACK_BUFFER`. If no buffer object is bound to this target, 0 is returned. When used with indexed variants of $(REF get) (such as $(REF getIntegeri_v)), $(I `data`) returns a single value, the name of the buffer object bound to the indexed transform feedback attribute stream. The initial value is 0 for all targets. See $(REF bindBuffer), $(REF bindBufferBase), and $(REF bindBufferRange).
	
	- `TRANSFORM_FEEDBACK_BUFFER_START`: When used with indexed variants of $(REF get) (such as $(REF getInteger64i_v)), $(I `data`) returns a single value, the start offset of the binding range for each transform feedback attribute stream. The initial value is 0 for all streams. See $(REF bindBufferRange).
	
	- `TRANSFORM_FEEDBACK_BUFFER_SIZE`: When used with indexed variants of $(REF get) (such as $(REF getInteger64i_v)), $(I `data`) returns a single value, the size of the binding range for each transform feedback attribute stream. The initial value is 0 for all streams. See $(REF bindBufferRange).
	
	- `UNIFORM_BUFFER_BINDING`: When used with non-indexed variants of $(REF get) (such as $(REF getIntegerv)), $(I `data`) returns a single value, the name of the buffer object currently bound to the target `UNIFORM_BUFFER`. If no buffer object is bound to this target, 0 is returned. When used with indexed variants of $(REF get) (such as $(REF getIntegeri_v)), $(I `data`) returns a single value, the name of the buffer object bound to the indexed uniform buffer binding point. The initial value is 0 for all targets. See $(REF bindBuffer), $(REF bindBufferBase), and $(REF bindBufferRange).
	
	- `UNIFORM_BUFFER_OFFSET_ALIGNMENT`: $(I `data`) returns a single value, the minimum required alignment for uniform buffer sizes and offset. The initial value is 1. See $(REF uniformBlockBinding).
	
	- `UNIFORM_BUFFER_SIZE`: When used with indexed variants of $(REF get) (such as $(REF getInteger64i_v)), $(I `data`) returns a single value, the size of the binding range for each indexed uniform buffer binding. The initial value is 0 for all bindings. See $(REF bindBufferRange).
	
	- `UNIFORM_BUFFER_START`: When used with indexed variants of $(REF get) (such as $(REF getInteger64i_v)), $(I `data`) returns a single value, the start offset of the binding range for each indexed uniform buffer binding. The initial value is 0 for all bindings. See $(REF bindBufferRange).
	
	- `UNPACK_ALIGNMENT`: $(I `data`) returns one value, the byte alignment used for reading pixel data from memory. The initial value is 4. See $(REF pixelStore).
	
	- `UNPACK_IMAGE_HEIGHT`: $(I `data`) returns one value, the image height used for reading pixel data from memory. The initial is 0. See $(REF pixelStore).
	
	- `UNPACK_LSB_FIRST`: $(I `data`) returns a single boolean value indicating whether single-bit pixels being read from memory are read first from the least significant bit of each unsigned byte. The initial value is `FALSE`. See $(REF pixelStore).
	
	- `UNPACK_ROW_LENGTH`: $(I `data`) returns one value, the row length used for reading pixel data from memory. The initial value is 0. See $(REF pixelStore).
	
	- `UNPACK_SKIP_IMAGES`: $(I `data`) returns one value, the number of pixel images skipped before the first pixel is read from memory. The initial value is 0. See $(REF pixelStore).
	
	- `UNPACK_SKIP_PIXELS`: $(I `data`) returns one value, the number of pixel locations skipped before the first pixel is read from memory. The initial value is 0. See $(REF pixelStore).
	
	- `UNPACK_SKIP_ROWS`: $(I `data`) returns one value, the number of rows of pixel locations skipped before the first pixel is read from memory. The initial value is 0. See $(REF pixelStore).
	
	- `UNPACK_SWAP_BYTES`: $(I `data`) returns a single boolean value indicating whether the bytes of two-byte and four-byte pixel indices and components are swapped after being read from memory. The initial value is `FALSE`. See $(REF pixelStore).
	
	- `VERTEX_ARRAY_BINDING`: $(I `data`) returns a single value, the name of the vertex array object currently bound to the context. If no vertex array object is bound to the context, 0 is returned. The initial value is 0. See $(REF bindVertexArray).
	
	- `VERTEX_BINDING_DIVISOR`: Accepted by the indexed forms. $(I `data`) returns a single integer value representing the instance step divisor of the first element in the bound buffer's data store for vertex attribute bound to $(I `index`).
	
	- `VERTEX_BINDING_OFFSET`: Accepted by the indexed forms. $(I `data`) returns a single integer value representing the byte offset of the first element in the bound buffer's data store for vertex attribute bound to $(I `index`).
	
	- `VERTEX_BINDING_STRIDE`: Accepted by the indexed forms. $(I `data`) returns a single integer value representing the byte offset between the start of each element in the bound buffer's data store for vertex attribute bound to $(I `index`).
	
	- `VERTEX_BINDING_BUFFER`: Accepted by the indexed forms. $(I `data`) returns a single integer value representing the name of the buffer bound to vertex binding $(I `index`).
	
	- `MAX_VERTEX_ATTRIB_RELATIVE_OFFSET`: $(I `data`) returns a single integer value containing the maximum offset that may be added to a vertex binding offset.
	
	- `MAX_VERTEX_ATTRIB_BINDINGS`: $(I `data`) returns a single integer value containing the maximum number of vertex buffers that may be bound.
	
	- `VIEWPORT`: When used with non-indexed variants of $(REF get) (such as $(REF getIntegerv)), $(I `data`) returns four values: the x and y window coordinates of the viewport, followed by its width and height. Initially the x and y window coordinates are both set to 0, and the width and height are set to the width and height of the window into which the GL will do its rendering. See $(REF viewport).   When used with indexed variants of $(REF get) (such as $(REF getIntegeri_v)), $(I `data`) returns four values: the x and y window coordinates of the indexed viewport, followed by its width and height. Initially the x and y window coordinates are both set to 0, and the width and height are set to the width and height of the window into which the GL will do its rendering. See $(REF viewportIndexedf).
	
	- `VIEWPORT_BOUNDS_RANGE`: $(I `data`) returns two values, the minimum and maximum viewport bounds range. The minimum range should be at least [-32768, 32767].
	
	- `VIEWPORT_INDEX_PROVOKING_VERTEX`: $(I `data`) returns one value, the implementation dependent specifc vertex of a primitive that is used to select the viewport index. If the value returned is equivalent to `PROVOKING_VERTEX`, then the vertex selection follows the convention specified by $(REF provokingVertex). If the value returned is equivalent to `FIRST_VERTEX_CONVENTION`, then the selection is always taken from the first vertex in the primitive. If the value returned is equivalent to `LAST_VERTEX_CONVENTION`, then the selection is always taken from the last vertex in the primitive. If the value returned is equivalent to `UNDEFINED_VERTEX`, then the selection is not guaranteed to be taken from any specific vertex in the primitive.
	
	- `VIEWPORT_SUBPIXEL_BITS`: $(I `data`) returns a single value, the number of bits of sub-pixel precision which the GL uses to interpret the floating point viewport bounds. The minimum value is 0.
	
	- `MAX_ELEMENT_INDEX`: $(I `data`) returns a single value, the maximum index that may be specified during the transfer of generic vertex attributes to the GL.
	
	Many of the boolean parameters can also be queried more easily using $(REF isEnabled).
	
	Params:
	pname = Specifies the parameter value to be returned for non-indexed versions of $(REF get). The symbolic constants in the list below are accepted.
	data = Returns the value or values of the specified parameter.
	*/
	void getDoublev(Enum pname, Double* data);
	
	/**
	$(REF getError) returns the value of the error flag. Each detectable error is assigned a numeric code and symbolic name. When an error occurs, the error flag is set to the appropriate error code value. No other errors are recorded until $(REF getError) is called, the error code is returned, and the flag is reset to `NO_ERROR`. If a call to $(REF getError) returns `NO_ERROR`, there has been no detectable error since the last call to $(REF getError), or since the GL was initialized.
	
	To allow for distributed implementations, there may be several error flags. If any single error flag has recorded an error, the value of that flag is returned and that flag is reset to `NO_ERROR` when $(REF getError) is called. If more than one flag has recorded an error, $(REF getError) returns and clears an arbitrary error flag value. Thus, $(REF getError) should always be called in a loop, until it returns `NO_ERROR`, if all error flags are to be reset.
	
	Initially, all error flags are set to `NO_ERROR`.
	
	The following errors are currently defined:
	
	- `NO_ERROR`: No error has been recorded. The value of this symbolic constant is guaranteed to be 0.
	
	- `INVALID_ENUM`: An unacceptable value is specified for an enumerated argument. The offending command is ignored and has no other side effect than to set the error flag.
	
	- `INVALID_VALUE`: A numeric argument is out of range. The offending command is ignored and has no other side effect than to set the error flag.
	
	- `INVALID_OPERATION`: The specified operation is not allowed in the current state. The offending command is ignored and has no other side effect than to set the error flag.
	
	- `INVALID_FRAMEBUFFER_OPERATION`: The framebuffer object is not complete. The offending command is ignored and has no other side effect than to set the error flag.
	
	- `OUT_OF_MEMORY`: There is not enough memory left to execute the command. The state of the GL is undefined, except for the state of the error flags, after this error is recorded.
	
	- `STACK_UNDERFLOW`: An attempt has been made to perform an operation that would cause an internal stack to underflow.
	
	- `STACK_OVERFLOW`: An attempt has been made to perform an operation that would cause an internal stack to overflow.
	
	When an error flag is set, results of a GL operation are undefined only if `OUT_OF_MEMORY` has occurred. In all other cases, the command generating the error is ignored and has no effect on the GL state or frame buffer contents. If the generating command returns a value, it returns 0. If $(REF getError) itself generates an error, it returns 0.
	
	Params:
	*/
	uint getError();
	
	/**
	These commands return values for simple state variables in GL. $(I `pname`) is a symbolic constant indicating the state variable to be returned, and $(I `data`) is a pointer to an array of the indicated type in which to place the returned data.
	
	Type conversion is performed if $(I `data`) has a different type than the state variable value being requested. If $(REF getBooleanv) is called, a floating-point (or integer) value is converted to `FALSE` if and only if it is 0.0 (or 0). Otherwise, it is converted to `TRUE`. If $(REF getIntegerv) is called, boolean values are returned as `TRUE` or `FALSE`, and most floating-point values are rounded to the nearest integer value. Floating-point colors and normals, however, are returned with a linear mapping that maps 1.0 to the most positive representable integer value and -1.0 to the most negative representable integer value. If $(REF getFloatv) or $(REF getDoublev) is called, boolean values are returned as `TRUE` or `FALSE`, and integer values are converted to floating-point values.
	
	The following symbolic constants are accepted by $(I `pname`):
	
	- `ACTIVE_TEXTURE`: $(I `data`) returns a single value indicating the active multitexture unit. The initial value is `TEXTURE0`. See $(REF activeTexture).
	
	- `ALIASED_LINE_WIDTH_RANGE`: $(I `data`) returns a pair of values indicating the range of widths supported for aliased lines. See $(REF lineWidth).
	
	- `ARRAY_BUFFER_BINDING`: $(I `data`) returns a single value, the name of the buffer object currently bound to the target `ARRAY_BUFFER`. If no buffer object is bound to this target, 0 is returned. The initial value is 0. See $(REF bindBuffer).
	
	- `BLEND`: $(I `data`) returns a single boolean value indicating whether blending is enabled. The initial value is `FALSE`. See $(REF blendFunc).
	
	- `BLEND_COLOR`: $(I `data`) returns four values, the red, green, blue, and alpha values which are the components of the blend color. See $(REF blendColor).
	
	- `BLEND_DST_ALPHA`: $(I `data`) returns one value, the symbolic constant identifying the alpha destination blend function. The initial value is `ZERO`. See $(REF blendFunc) and $(REF blendFuncSeparate).
	
	- `BLEND_DST_RGB`: $(I `data`) returns one value, the symbolic constant identifying the RGB destination blend function. The initial value is `ZERO`. See $(REF blendFunc) and $(REF blendFuncSeparate).
	
	- `BLEND_EQUATION_RGB`: $(I `data`) returns one value, a symbolic constant indicating whether the RGB blend equation is `FUNC_ADD`, `FUNC_SUBTRACT`, `FUNC_REVERSE_SUBTRACT`, `MIN` or `MAX`. See $(REF blendEquationSeparate).
	
	- `BLEND_EQUATION_ALPHA`: $(I `data`) returns one value, a symbolic constant indicating whether the Alpha blend equation is `FUNC_ADD`, `FUNC_SUBTRACT`, `FUNC_REVERSE_SUBTRACT`, `MIN` or `MAX`. See $(REF blendEquationSeparate).
	
	- `BLEND_SRC_ALPHA`: $(I `data`) returns one value, the symbolic constant identifying the alpha source blend function. The initial value is `ONE`. See $(REF blendFunc) and $(REF blendFuncSeparate).
	
	- `BLEND_SRC_RGB`: $(I `data`) returns one value, the symbolic constant identifying the RGB source blend function. The initial value is `ONE`. See $(REF blendFunc) and $(REF blendFuncSeparate).
	
	- `COLOR_CLEAR_VALUE`: $(I `data`) returns four values: the red, green, blue, and alpha values used to clear the color buffers. Integer values, if requested, are linearly mapped from the internal floating-point representation such that 1.0 returns the most positive representable integer value, and  -1.0  returns the most negative representable integer value. The initial value is (0, 0, 0, 0). See $(REF clearColor).
	
	- `COLOR_LOGIC_OP`: $(I `data`) returns a single boolean value indicating whether a fragment's RGBA color values are merged into the framebuffer using a logical operation. The initial value is `FALSE`. See $(REF logicOp).
	
	- `COLOR_WRITEMASK`: $(I `data`) returns four boolean values: the red, green, blue, and alpha write enables for the color buffers. The initial value is (`TRUE`, `TRUE`, `TRUE`, `TRUE`). See $(REF colorMask).
	
	- `COMPRESSED_TEXTURE_FORMATS`: $(I `data`) returns a list of symbolic constants of length `NUM_COMPRESSED_TEXTURE_FORMATS` indicating which compressed texture formats are available. See $(REF compressedTexImage2D).
	
	- `MAX_COMPUTE_SHADER_STORAGE_BLOCKS`: $(I `data`) returns one value, the maximum number of active shader storage blocks that may be accessed by a compute shader.
	
	- `MAX_COMBINED_SHADER_STORAGE_BLOCKS`: $(I `data`) returns one value, the maximum total number of active shader storage blocks that may be accessed by all active shaders.
	
	- `MAX_COMPUTE_UNIFORM_BLOCKS`: $(I `data`) returns one value, the maximum number of uniform blocks per compute shader. The value must be at least 14. See $(REF uniformBlockBinding).
	
	- `MAX_COMPUTE_TEXTURE_IMAGE_UNITS`: $(I `data`) returns one value, the maximum supported texture image units that can be used to access texture maps from the compute shader. The value may be at least 16. See $(REF activeTexture).
	
	- `MAX_COMPUTE_UNIFORM_COMPONENTS`: $(I `data`) returns one value, the maximum number of individual floating-point, integer, or boolean values that can be held in uniform variable storage for a compute shader. The value must be at least 1024. See $(REF uniform).
	
	- `MAX_COMPUTE_ATOMIC_COUNTERS`: $(I `data`) returns a single value, the maximum number of atomic counters available to compute shaders.
	
	- `MAX_COMPUTE_ATOMIC_COUNTER_BUFFERS`: $(I `data`) returns a single value, the maximum number of atomic counter buffers that may be accessed by a compute shader.
	
	- `MAX_COMBINED_COMPUTE_UNIFORM_COMPONENTS`: $(I `data`) returns one value, the number of words for compute shader uniform variables in all uniform blocks (including default). The value must be at least 1. See $(REF uniform).
	
	- `MAX_COMPUTE_WORK_GROUP_INVOCATIONS`: $(I `data`) returns one value, the number of invocations in a single local work group (i.e., the product of the three dimensions) that may be dispatched to a compute shader.
	
	- `MAX_COMPUTE_WORK_GROUP_COUNT`: Accepted by the indexed versions of $(REF get). $(I `data`) the maximum number of work groups that may be dispatched to a compute shader. Indices 0, 1, and 2 correspond to the X, Y and Z dimensions, respectively.
	
	- `MAX_COMPUTE_WORK_GROUP_SIZE`: Accepted by the indexed versions of $(REF get). $(I `data`) the maximum size of a work groups that may be used during compilation of a compute shader. Indices 0, 1, and 2 correspond to the X, Y and Z dimensions, respectively.
	
	- `DISPATCH_INDIRECT_BUFFER_BINDING`: $(I `data`) returns a single value, the name of the buffer object currently bound to the target `DISPATCH_INDIRECT_BUFFER`. If no buffer object is bound to this target, 0 is returned. The initial value is 0. See $(REF bindBuffer).
	
	- `MAX_DEBUG_GROUP_STACK_DEPTH`: $(I `data`) returns a single value, the maximum depth of the debug message group stack.
	
	- `DEBUG_GROUP_STACK_DEPTH`: $(I `data`) returns a single value, the current depth of the debug message group stack.
	
	- `CONTEXT_FLAGS`: $(I `data`) returns one value, the flags with which the context was created (such as debugging functionality).
	
	- `CULL_FACE`: $(I `data`) returns a single boolean value indicating whether polygon culling is enabled. The initial value is `FALSE`. See $(REF cullFace).
	
	- `CULL_FACE_MODE`: $(I `data`) returns a single value indicating the mode of polygon culling. The initial value is `BACK`. See $(REF cullFace).
	
	- `CURRENT_PROGRAM`: $(I `data`) returns one value, the name of the program object that is currently active, or 0 if no program object is active. See $(REF useProgram).
	
	- `DEPTH_CLEAR_VALUE`: $(I `data`) returns one value, the value that is used to clear the depth buffer. Integer values, if requested, are linearly mapped from the internal floating-point representation such that 1.0 returns the most positive representable integer value, and  -1.0  returns the most negative representable integer value. The initial value is 1. See $(REF clearDepth).
	
	- `DEPTH_FUNC`: $(I `data`) returns one value, the symbolic constant that indicates the depth comparison function. The initial value is `LESS`. See $(REF depthFunc).
	
	- `DEPTH_RANGE`: $(I `data`) returns two values: the near and far mapping limits for the depth buffer. Integer values, if requested, are linearly mapped from the internal floating-point representation such that 1.0 returns the most positive representable integer value, and  -1.0  returns the most negative representable integer value. The initial value is (0, 1). See $(REF depthRange).
	
	- `DEPTH_TEST`: $(I `data`) returns a single boolean value indicating whether depth testing of fragments is enabled. The initial value is `FALSE`. See $(REF depthFunc) and $(REF depthRange).
	
	- `DEPTH_WRITEMASK`: $(I `data`) returns a single boolean value indicating if the depth buffer is enabled for writing. The initial value is `TRUE`. See $(REF depthMask).
	
	- `DITHER`: $(I `data`) returns a single boolean value indicating whether dithering of fragment colors and indices is enabled. The initial value is `TRUE`.
	
	- `DOUBLEBUFFER`: $(I `data`) returns a single boolean value indicating whether double buffering is supported.
	
	- `DRAW_BUFFER`: $(I `data`) returns one value, a symbolic constant indicating which buffers are being drawn to. See $(REF drawBuffer). The initial value is `BACK` if there are back buffers, otherwise it is `FRONT`.
	
	- `DRAW_BUFFER`  $(I i): $(I `data`) returns one value, a symbolic constant indicating which buffers are being drawn to by the corresponding output color. See $(REF drawBuffers). The initial value of `DRAW_BUFFER0` is `BACK` if there are back buffers, otherwise it is `FRONT`. The initial values of draw buffers for all other output colors is `NONE`.
	
	- `DRAW_FRAMEBUFFER_BINDING`: $(I `data`) returns one value, the name of the framebuffer object currently bound to the `DRAW_FRAMEBUFFER` target. If the default framebuffer is bound, this value will be zero. The initial value is zero. See $(REF bindFramebuffer).
	
	- `READ_FRAMEBUFFER_BINDING`: $(I `data`) returns one value, the name of the framebuffer object currently bound to the `READ_FRAMEBUFFER` target. If the default framebuffer is bound, this value will be zero. The initial value is zero. See $(REF bindFramebuffer).
	
	- `ELEMENT_ARRAY_BUFFER_BINDING`: $(I `data`) returns a single value, the name of the buffer object currently bound to the target `ELEMENT_ARRAY_BUFFER`. If no buffer object is bound to this target, 0 is returned. The initial value is 0. See $(REF bindBuffer).
	
	- `FRAGMENT_SHADER_DERIVATIVE_HINT`: $(I `data`) returns one value, a symbolic constant indicating the mode of the derivative accuracy hint for fragment shaders. The initial value is `DONT_CARE`. See $(REF hint).
	
	- `IMPLEMENTATION_COLOR_READ_FORMAT`: $(I `data`) returns a single GLenum value indicating the implementation's preferred pixel data format. See $(REF readPixels).
	
	- `IMPLEMENTATION_COLOR_READ_TYPE`: $(I `data`) returns a single GLenum value indicating the implementation's preferred pixel data type. See $(REF readPixels).
	
	- `LINE_SMOOTH`: $(I `data`) returns a single boolean value indicating whether antialiasing of lines is enabled. The initial value is `FALSE`. See $(REF lineWidth).
	
	- `LINE_SMOOTH_HINT`: $(I `data`) returns one value, a symbolic constant indicating the mode of the line antialiasing hint. The initial value is `DONT_CARE`. See $(REF hint).
	
	- `LINE_WIDTH`: $(I `data`) returns one value, the line width as specified with $(REF lineWidth). The initial value is 1.
	
	- `LAYER_PROVOKING_VERTEX`: $(I `data`) returns one value, the implementation dependent specifc vertex of a primitive that is used to select the rendering layer. If the value returned is equivalent to `PROVOKING_VERTEX`, then the vertex selection follows the convention specified by $(REF provokingVertex). If the value returned is equivalent to `FIRST_VERTEX_CONVENTION`, then the selection is always taken from the first vertex in the primitive. If the value returned is equivalent to `LAST_VERTEX_CONVENTION`, then the selection is always taken from the last vertex in the primitive. If the value returned is equivalent to `UNDEFINED_VERTEX`, then the selection is not guaranteed to be taken from any specific vertex in the primitive.
	
	- `LOGIC_OP_MODE`: $(I `data`) returns one value, a symbolic constant indicating the selected logic operation mode. The initial value is `COPY`. See $(REF logicOp).
	
	- `MAJOR_VERSION`: $(I `data`) returns one value, the major version number of the OpenGL API supported by the current context.
	
	- `MAX_3D_TEXTURE_SIZE`: $(I `data`) returns one value, a rough estimate of the largest 3D texture that the GL can handle. The value must be at least 64. Use `PROXY_TEXTURE_3D` to determine if a texture is too large. See $(REF texImage3D).
	
	- `MAX_ARRAY_TEXTURE_LAYERS`: $(I `data`) returns one value. The value indicates the maximum number of layers allowed in an array texture, and must be at least 256. See $(REF texImage2D).
	
	- `MAX_CLIP_DISTANCES`: $(I `data`) returns one value, the maximum number of application-defined clipping distances. The value must be at least 8.
	
	- `MAX_COLOR_TEXTURE_SAMPLES`: $(I `data`) returns one value, the maximum number of samples in a color multisample texture.
	
	- `MAX_COMBINED_ATOMIC_COUNTERS`: $(I `data`) returns a single value, the maximum number of atomic counters available to all active shaders.
	
	- `MAX_COMBINED_FRAGMENT_UNIFORM_COMPONENTS`: $(I `data`) returns one value, the number of words for fragment shader uniform variables in all uniform blocks (including default). The value must be at least 1. See $(REF uniform).
	
	- `MAX_COMBINED_GEOMETRY_UNIFORM_COMPONENTS`: $(I `data`) returns one value, the number of words for geometry shader uniform variables in all uniform blocks (including default). The value must be at least 1. See $(REF uniform).
	
	- `MAX_COMBINED_TEXTURE_IMAGE_UNITS`: $(I `data`) returns one value, the maximum supported texture image units that can be used to access texture maps from the vertex shader and the fragment processor combined. If both the vertex shader and the fragment processing stage access the same texture image unit, then that counts as using two texture image units against this limit. The value must be at least 48. See $(REF activeTexture).
	
	- `MAX_COMBINED_UNIFORM_BLOCKS`: $(I `data`) returns one value, the maximum number of uniform blocks per program. The value must be at least 70. See $(REF uniformBlockBinding).
	
	- `MAX_COMBINED_VERTEX_UNIFORM_COMPONENTS`: $(I `data`) returns one value, the number of words for vertex shader uniform variables in all uniform blocks (including default). The value must be at least 1. See $(REF uniform).
	
	- `MAX_CUBE_MAP_TEXTURE_SIZE`: $(I `data`) returns one value. The value gives a rough estimate of the largest cube-map texture that the GL can handle. The value must be at least 1024. Use `PROXY_TEXTURE_CUBE_MAP` to determine if a texture is too large. See $(REF texImage2D).
	
	- `MAX_DEPTH_TEXTURE_SAMPLES`: $(I `data`) returns one value, the maximum number of samples in a multisample depth or depth-stencil texture.
	
	- `MAX_DRAW_BUFFERS`: $(I `data`) returns one value, the maximum number of simultaneous outputs that may be written in a fragment shader. The value must be at least 8. See $(REF drawBuffers).
	
	- `MAX_DUAL_SOURCE_DRAW_BUFFERS`: $(I `data`) returns one value, the maximum number of active draw buffers when using dual-source blending. The value must be at least 1. See $(REF blendFunc) and $(REF blendFuncSeparate).
	
	- `MAX_ELEMENTS_INDICES`: $(I `data`) returns one value, the recommended maximum number of vertex array indices. See $(REF drawRangeElements).
	
	- `MAX_ELEMENTS_VERTICES`: $(I `data`) returns one value, the recommended maximum number of vertex array vertices. See $(REF drawRangeElements).
	
	- `MAX_FRAGMENT_ATOMIC_COUNTERS`: $(I `data`) returns a single value, the maximum number of atomic counters available to fragment shaders.
	
	- `MAX_FRAGMENT_SHADER_STORAGE_BLOCKS`: $(I `data`) returns one value, the maximum number of active shader storage blocks that may be accessed by a fragment shader.
	
	- `MAX_FRAGMENT_INPUT_COMPONENTS`: $(I `data`) returns one value, the maximum number of components of the inputs read by the fragment shader, which must be at least 128.
	
	- `MAX_FRAGMENT_UNIFORM_COMPONENTS`: $(I `data`) returns one value, the maximum number of individual floating-point, integer, or boolean values that can be held in uniform variable storage for a fragment shader. The value must be at least 1024. See $(REF uniform).
	
	- `MAX_FRAGMENT_UNIFORM_VECTORS`: $(I `data`) returns one value, the maximum number of individual 4-vectors of floating-point, integer, or boolean values that can be held in uniform variable storage for a fragment shader. The value is equal to the value of `MAX_FRAGMENT_UNIFORM_COMPONENTS` divided by 4 and must be at least 256. See $(REF uniform).
	
	- `MAX_FRAGMENT_UNIFORM_BLOCKS`: $(I `data`) returns one value, the maximum number of uniform blocks per fragment shader. The value must be at least 12. See $(REF uniformBlockBinding).
	
	- `MAX_FRAMEBUFFER_WIDTH`: $(I `data`) returns one value, the maximum width for a framebuffer that has no attachments, which must be at least 16384. See $(REF framebufferParameter).
	
	- `MAX_FRAMEBUFFER_HEIGHT`: $(I `data`) returns one value, the maximum height for a framebuffer that has no attachments, which must be at least 16384. See $(REF framebufferParameter).
	
	- `MAX_FRAMEBUFFER_LAYERS`: $(I `data`) returns one value, the maximum number of layers for a framebuffer that has no attachments, which must be at least 2048. See $(REF framebufferParameter).
	
	- `MAX_FRAMEBUFFER_SAMPLES`: $(I `data`) returns one value, the maximum samples in a framebuffer that has no attachments, which must be at least 4. See $(REF framebufferParameter).
	
	- `MAX_GEOMETRY_ATOMIC_COUNTERS`: $(I `data`) returns a single value, the maximum number of atomic counters available to geometry shaders.
	
	- `MAX_GEOMETRY_SHADER_STORAGE_BLOCKS`: $(I `data`) returns one value, the maximum number of active shader storage blocks that may be accessed by a geometry shader.
	
	- `MAX_GEOMETRY_INPUT_COMPONENTS`: $(I `data`) returns one value, the maximum number of components of inputs read by a geometry shader, which must be at least 64.
	
	- `MAX_GEOMETRY_OUTPUT_COMPONENTS`: $(I `data`) returns one value, the maximum number of components of outputs written by a geometry shader, which must be at least 128.
	
	- `MAX_GEOMETRY_TEXTURE_IMAGE_UNITS`: $(I `data`) returns one value, the maximum supported texture image units that can be used to access texture maps from the geometry shader. The value must be at least 16. See $(REF activeTexture).
	
	- `MAX_GEOMETRY_UNIFORM_BLOCKS`: $(I `data`) returns one value, the maximum number of uniform blocks per geometry shader. The value must be at least 12. See $(REF uniformBlockBinding).
	
	- `MAX_GEOMETRY_UNIFORM_COMPONENTS`: $(I `data`) returns one value, the maximum number of individual floating-point, integer, or boolean values that can be held in uniform variable storage for a geometry shader. The value must be at least 1024. See $(REF uniform).
	
	- `MAX_INTEGER_SAMPLES`: $(I `data`) returns one value, the maximum number of samples supported in integer format multisample buffers.
	
	- `MIN_MAP_BUFFER_ALIGNMENT`: $(I `data`) returns one value, the minimum alignment in basic machine units of pointers returned from$(REF mapBuffer) and $(REF mapBufferRange). This value must be a power of two and must be at least 64.
	
	- `MAX_LABEL_LENGTH`: $(I `data`) returns one value, the maximum length of a label that may be assigned to an object. See $(REF objectLabel) and $(REF objectPtrLabel).
	
	- `MAX_PROGRAM_TEXEL_OFFSET`: $(I `data`) returns one value, the maximum texel offset allowed in a texture lookup, which must be at least 7.
	
	- `MIN_PROGRAM_TEXEL_OFFSET`: $(I `data`) returns one value, the minimum texel offset allowed in a texture lookup, which must be at most -8.
	
	- `MAX_RECTANGLE_TEXTURE_SIZE`: $(I `data`) returns one value. The value gives a rough estimate of the largest rectangular texture that the GL can handle. The value must be at least 1024. Use `PROXY_TEXTURE_RECTANGLE` to determine if a texture is too large. See $(REF texImage2D).
	
	- `MAX_RENDERBUFFER_SIZE`: $(I `data`) returns one value. The value indicates the maximum supported size for renderbuffers. See $(REF framebufferRenderbuffer).
	
	- `MAX_SAMPLE_MASK_WORDS`: $(I `data`) returns one value, the maximum number of sample mask words.
	
	- `MAX_SERVER_WAIT_TIMEOUT`: $(I `data`) returns one value, the maximum $(REF waitSync) timeout interval.
	
	- `MAX_SHADER_STORAGE_BUFFER_BINDINGS`: $(I `data`) returns one value, the maximum number of shader storage buffer binding points on the context, which must be at least 8.
	
	- `MAX_TESS_CONTROL_ATOMIC_COUNTERS`: $(I `data`) returns a single value, the maximum number of atomic counters available to tessellation control shaders.
	
	- `MAX_TESS_EVALUATION_ATOMIC_COUNTERS`: $(I `data`) returns a single value, the maximum number of atomic counters available to tessellation evaluation shaders.
	
	- `MAX_TESS_CONTROL_SHADER_STORAGE_BLOCKS`: $(I `data`) returns one value, the maximum number of active shader storage blocks that may be accessed by a tessellation control shader.
	
	- `MAX_TESS_EVALUATION_SHADER_STORAGE_BLOCKS`: $(I `data`) returns one value, the maximum number of active shader storage blocks that may be accessed by a tessellation evaluation shader.
	
	- `MAX_TEXTURE_BUFFER_SIZE`: $(I `data`) returns one value. The value gives the maximum number of texels allowed in the texel array of a texture buffer object. Value must be at least 65536.
	
	- `MAX_TEXTURE_IMAGE_UNITS`: $(I `data`) returns one value, the maximum supported texture image units that can be used to access texture maps from the fragment shader. The value must be at least 16. See $(REF activeTexture).
	
	- `MAX_TEXTURE_LOD_BIAS`: $(I `data`) returns one value, the maximum, absolute value of the texture level-of-detail bias. The value must be at least 2.0.
	
	- `MAX_TEXTURE_SIZE`: $(I `data`) returns one value. The value gives a rough estimate of the largest texture that the GL can handle. The value must be at least 1024. Use a proxy texture target such as `PROXY_TEXTURE_1D` or `PROXY_TEXTURE_2D` to determine if a texture is too large. See $(REF texImage1D) and $(REF texImage2D).
	
	- `MAX_UNIFORM_BUFFER_BINDINGS`: $(I `data`) returns one value, the maximum number of uniform buffer binding points on the context, which must be at least 36.
	
	- `MAX_UNIFORM_BLOCK_SIZE`: $(I `data`) returns one value, the maximum size in basic machine units of a uniform block, which must be at least 16384.
	
	- `MAX_UNIFORM_LOCATIONS`: $(I `data`) returns one value, the maximum number of explicitly assignable uniform locations, which must be at least 1024.
	
	- `MAX_VARYING_COMPONENTS`: $(I `data`) returns one value, the number components for varying variables, which must be at least 60.
	
	- `MAX_VARYING_VECTORS`: $(I `data`) returns one value, the number 4-vectors for varying variables, which is equal to the value of `MAX_VARYING_COMPONENTS` and must be at least 15.
	
	- `MAX_VARYING_FLOATS`: $(I `data`) returns one value, the maximum number of interpolators available for processing varying variables used by vertex and fragment shaders. This value represents the number of individual floating-point values that can be interpolated; varying variables declared as vectors, matrices, and arrays will all consume multiple interpolators. The value must be at least 32.
	
	- `MAX_VERTEX_ATOMIC_COUNTERS`: $(I `data`) returns a single value, the maximum number of atomic counters available to vertex shaders.
	
	- `MAX_VERTEX_ATTRIBS`: $(I `data`) returns one value, the maximum number of 4-component generic vertex attributes accessible to a vertex shader. The value must be at least 16. See $(REF vertexAttrib).
	
	- `MAX_VERTEX_SHADER_STORAGE_BLOCKS`: $(I `data`) returns one value, the maximum number of active shader storage blocks that may be accessed by a vertex shader.
	
	- `MAX_VERTEX_TEXTURE_IMAGE_UNITS`: $(I `data`) returns one value, the maximum supported texture image units that can be used to access texture maps from the vertex shader. The value may be at least 16. See $(REF activeTexture).
	
	- `MAX_VERTEX_UNIFORM_COMPONENTS`: $(I `data`) returns one value, the maximum number of individual floating-point, integer, or boolean values that can be held in uniform variable storage for a vertex shader. The value must be at least 1024. See $(REF uniform).
	
	- `MAX_VERTEX_UNIFORM_VECTORS`: $(I `data`) returns one value, the maximum number of 4-vectors that may be held in uniform variable storage for the vertex shader. The value of `MAX_VERTEX_UNIFORM_VECTORS` is equal to the value of `MAX_VERTEX_UNIFORM_COMPONENTS` and must be at least 256.
	
	- `MAX_VERTEX_OUTPUT_COMPONENTS`: $(I `data`) returns one value, the maximum number of components of output written by a vertex shader, which must be at least 64.
	
	- `MAX_VERTEX_UNIFORM_BLOCKS`: $(I `data`) returns one value, the maximum number of uniform blocks per vertex shader. The value must be at least 12. See $(REF uniformBlockBinding).
	
	- `MAX_VIEWPORT_DIMS`: $(I `data`) returns two values: the maximum supported width and height of the viewport. These must be at least as large as the visible dimensions of the display being rendered to. See $(REF viewport).
	
	- `MAX_VIEWPORTS`: $(I `data`) returns one value, the maximum number of simultaneous viewports that are supported. The value must be at least 16. See $(REF viewportIndexed).
	
	- `MINOR_VERSION`: $(I `data`) returns one value, the minor version number of the OpenGL API supported by the current context.
	
	- `NUM_COMPRESSED_TEXTURE_FORMATS`: $(I `data`) returns a single integer value indicating the number of available compressed texture formats. The minimum value is 4. See $(REF compressedTexImage2D).
	
	- `NUM_EXTENSIONS`: $(I `data`) returns one value, the number of extensions supported by the GL implementation for the current context. See $(REF getString).
	
	- `NUM_PROGRAM_BINARY_FORMATS`: $(I `data`) returns one value, the number of program binary formats supported by the implementation.
	
	- `NUM_SHADER_BINARY_FORMATS`: $(I `data`) returns one value, the number of binary shader formats supported by the implementation. If this value is greater than zero, then the implementation supports loading binary shaders. If it is zero, then the loading of binary shaders by the implementation is not supported.
	
	- `PACK_ALIGNMENT`: $(I `data`) returns one value, the byte alignment used for writing pixel data to memory. The initial value is 4. See $(REF pixelStore).
	
	- `PACK_IMAGE_HEIGHT`: $(I `data`) returns one value, the image height used for writing pixel data to memory. The initial value is 0. See $(REF pixelStore).
	
	- `PACK_LSB_FIRST`: $(I `data`) returns a single boolean value indicating whether single-bit pixels being written to memory are written first to the least significant bit of each unsigned byte. The initial value is `FALSE`. See $(REF pixelStore).
	
	- `PACK_ROW_LENGTH`: $(I `data`) returns one value, the row length used for writing pixel data to memory. The initial value is 0. See $(REF pixelStore).
	
	- `PACK_SKIP_IMAGES`: $(I `data`) returns one value, the number of pixel images skipped before the first pixel is written into memory. The initial value is 0. See $(REF pixelStore).
	
	- `PACK_SKIP_PIXELS`: $(I `data`) returns one value, the number of pixel locations skipped before the first pixel is written into memory. The initial value is 0. See $(REF pixelStore).
	
	- `PACK_SKIP_ROWS`: $(I `data`) returns one value, the number of rows of pixel locations skipped before the first pixel is written into memory. The initial value is 0. See $(REF pixelStore).
	
	- `PACK_SWAP_BYTES`: $(I `data`) returns a single boolean value indicating whether the bytes of two-byte and four-byte pixel indices and components are swapped before being written to memory. The initial value is `FALSE`. See $(REF pixelStore).
	
	- `PIXEL_PACK_BUFFER_BINDING`: $(I `data`) returns a single value, the name of the buffer object currently bound to the target `PIXEL_PACK_BUFFER`. If no buffer object is bound to this target, 0 is returned. The initial value is 0. See $(REF bindBuffer).
	
	- `PIXEL_UNPACK_BUFFER_BINDING`: $(I `data`) returns a single value, the name of the buffer object currently bound to the target `PIXEL_UNPACK_BUFFER`. If no buffer object is bound to this target, 0 is returned. The initial value is 0. See $(REF bindBuffer).
	
	- `POINT_FADE_THRESHOLD_SIZE`: $(I `data`) returns one value, the point size threshold for determining the point size. See $(REF pointParameter).
	
	- `PRIMITIVE_RESTART_INDEX`: $(I `data`) returns one value, the current primitive restart index. The initial value is 0. See $(REF primitiveRestartIndex).
	
	- `PROGRAM_BINARY_FORMATS`: $(I `data`) an array of `NUM_PROGRAM_BINARY_FORMATS` values, indicating the proram binary formats supported by the implementation.
	
	- `PROGRAM_PIPELINE_BINDING`: $(I `data`) a single value, the name of the currently bound program pipeline object, or zero if no program pipeline object is bound. See $(REF bindProgramPipeline).
	
	- `PROGRAM_POINT_SIZE`: $(I `data`) returns a single boolean value indicating whether vertex program point size mode is enabled. If enabled, then the point size is taken from the shader built-in `gl_PointSize`. If disabled, then the point size is taken from the point state as specified by $(REF pointSize). The initial value is `FALSE`.
	
	- `PROVOKING_VERTEX`: $(I `data`) returns one value, the currently selected provoking vertex convention. The initial value is `LAST_VERTEX_CONVENTION`. See $(REF provokingVertex).
	
	- `POINT_SIZE`: $(I `data`) returns one value, the point size as specified by $(REF pointSize). The initial value is 1.
	
	- `POINT_SIZE_GRANULARITY`: $(I `data`) returns one value, the size difference between adjacent supported sizes for antialiased points. See $(REF pointSize).
	
	- `POINT_SIZE_RANGE`: $(I `data`) returns two values: the smallest and largest supported sizes for antialiased points. The smallest size must be at most 1, and the largest size must be at least 1. See $(REF pointSize).
	
	- `POLYGON_OFFSET_FACTOR`: $(I `data`) returns one value, the scaling factor used to determine the variable offset that is added to the depth value of each fragment generated when a polygon is rasterized. The initial value is 0. See $(REF polygonOffset).
	
	- `POLYGON_OFFSET_UNITS`: $(I `data`) returns one value. This value is multiplied by an implementation-specific value and then added to the depth value of each fragment generated when a polygon is rasterized. The initial value is 0. See $(REF polygonOffset).
	
	- `POLYGON_OFFSET_FILL`: $(I `data`) returns a single boolean value indicating whether polygon offset is enabled for polygons in fill mode. The initial value is `FALSE`. See $(REF polygonOffset).
	
	- `POLYGON_OFFSET_LINE`: $(I `data`) returns a single boolean value indicating whether polygon offset is enabled for polygons in line mode. The initial value is `FALSE`. See $(REF polygonOffset).
	
	- `POLYGON_OFFSET_POINT`: $(I `data`) returns a single boolean value indicating whether polygon offset is enabled for polygons in point mode. The initial value is `FALSE`. See $(REF polygonOffset).
	
	- `POLYGON_SMOOTH`: $(I `data`) returns a single boolean value indicating whether antialiasing of polygons is enabled. The initial value is `FALSE`. See $(REF polygonMode).
	
	- `POLYGON_SMOOTH_HINT`: $(I `data`) returns one value, a symbolic constant indicating the mode of the polygon antialiasing hint. The initial value is `DONT_CARE`. See $(REF hint).
	
	- `READ_BUFFER`: $(I `data`) returns one value, a symbolic constant indicating which color buffer is selected for reading. The initial value is `BACK` if there is a back buffer, otherwise it is `FRONT`. See $(REF readPixels).
	
	- `RENDERBUFFER_BINDING`: $(I `data`) returns a single value, the name of the renderbuffer object currently bound to the target `RENDERBUFFER`. If no renderbuffer object is bound to this target, 0 is returned. The initial value is 0. See $(REF bindRenderbuffer).
	
	- `SAMPLE_BUFFERS`: $(I `data`) returns a single integer value indicating the number of sample buffers associated with the framebuffer. See $(REF sampleCoverage).
	
	- `SAMPLE_COVERAGE_VALUE`: $(I `data`) returns a single positive floating-point value indicating the current sample coverage value. See $(REF sampleCoverage).
	
	- `SAMPLE_COVERAGE_INVERT`: $(I `data`) returns a single boolean value indicating if the temporary coverage value should be inverted. See $(REF sampleCoverage).
	
	- `SAMPLER_BINDING`: $(I `data`) returns a single value, the name of the sampler object currently bound to the active texture unit. The initial value is 0. See $(REF bindSampler).
	
	- `SAMPLES`: $(I `data`) returns a single integer value indicating the coverage mask size. See $(REF sampleCoverage).
	
	- `SCISSOR_BOX`: $(I `data`) returns four values: the x and y window coordinates of the scissor box, followed by its width and height. Initially the x and y window coordinates are both 0 and the width and height are set to the size of the window. See $(REF scissor).
	
	- `SCISSOR_TEST`: $(I `data`) returns a single boolean value indicating whether scissoring is enabled. The initial value is `FALSE`. See $(REF scissor).
	
	- `SHADER_COMPILER`: $(I `data`) returns a single boolean value indicating whether an online shader compiler is present in the implementation. All desktop OpenGL implementations must support online shader compilations, and therefore the value of `SHADER_COMPILER` will always be `TRUE`.
	
	- `SHADER_STORAGE_BUFFER_BINDING`: When used with non-indexed variants of $(REF get) (such as $(REF getIntegerv)), $(I `data`) returns a single value, the name of the buffer object currently bound to the target `SHADER_STORAGE_BUFFER`. If no buffer object is bound to this target, 0 is returned. When used with indexed variants of $(REF get) (such as $(REF getIntegeri_v)), $(I `data`) returns a single value, the name of the buffer object bound to the indexed shader storage buffer binding points. The initial value is 0 for all targets. See $(REF bindBuffer), $(REF bindBufferBase), and $(REF bindBufferRange).
	
	- `SHADER_STORAGE_BUFFER_OFFSET_ALIGNMENT`: $(I `data`) returns a single value, the minimum required alignment for shader storage buffer sizes and offset. The initial value is 1. See $(REF shaderStorageBlockBinding).
	
	- `SHADER_STORAGE_BUFFER_START`: When used with indexed variants of $(REF get) (such as $(REF getInteger64i_v)), $(I `data`) returns a single value, the start offset of the binding range for each indexed shader storage buffer binding. The initial value is 0 for all bindings. See $(REF bindBufferRange).
	
	- `SHADER_STORAGE_BUFFER_SIZE`: When used with indexed variants of $(REF get) (such as $(REF getInteger64i_v)), $(I `data`) returns a single value, the size of the binding range for each indexed shader storage buffer binding. The initial value is 0 for all bindings. See $(REF bindBufferRange).
	
	- `SMOOTH_LINE_WIDTH_RANGE`: $(I `data`) returns a pair of values indicating the range of widths supported for smooth (antialiased) lines. See $(REF lineWidth).
	
	- `SMOOTH_LINE_WIDTH_GRANULARITY`: $(I `data`) returns a single value indicating the level of quantization applied to smooth line width parameters.
	
	- `STENCIL_BACK_FAIL`: $(I `data`) returns one value, a symbolic constant indicating what action is taken for back-facing polygons when the stencil test fails. The initial value is `KEEP`. See $(REF stencilOpSeparate).
	
	- `STENCIL_BACK_FUNC`: $(I `data`) returns one value, a symbolic constant indicating what function is used for back-facing polygons to compare the stencil reference value with the stencil buffer value. The initial value is `ALWAYS`. See $(REF stencilFuncSeparate).
	
	- `STENCIL_BACK_PASS_DEPTH_FAIL`: $(I `data`) returns one value, a symbolic constant indicating what action is taken for back-facing polygons when the stencil test passes, but the depth test fails. The initial value is `KEEP`. See $(REF stencilOpSeparate).
	
	- `STENCIL_BACK_PASS_DEPTH_PASS`: $(I `data`) returns one value, a symbolic constant indicating what action is taken for back-facing polygons when the stencil test passes and the depth test passes. The initial value is `KEEP`. See $(REF stencilOpSeparate).
	
	- `STENCIL_BACK_REF`: $(I `data`) returns one value, the reference value that is compared with the contents of the stencil buffer for back-facing polygons. The initial value is 0. See $(REF stencilFuncSeparate).
	
	- `STENCIL_BACK_VALUE_MASK`: $(I `data`) returns one value, the mask that is used for back-facing polygons to mask both the stencil reference value and the stencil buffer value before they are compared. The initial value is all 1's. See $(REF stencilFuncSeparate).
	
	- `STENCIL_BACK_WRITEMASK`: $(I `data`) returns one value, the mask that controls writing of the stencil bitplanes for back-facing polygons. The initial value is all 1's. See $(REF stencilMaskSeparate).
	
	- `STENCIL_CLEAR_VALUE`: $(I `data`) returns one value, the index to which the stencil bitplanes are cleared. The initial value is 0. See $(REF clearStencil).
	
	- `STENCIL_FAIL`: $(I `data`) returns one value, a symbolic constant indicating what action is taken when the stencil test fails. The initial value is `KEEP`. See $(REF stencilOp). This stencil state only affects non-polygons and front-facing polygons. Back-facing polygons use separate stencil state. See $(REF stencilOpSeparate).
	
	- `STENCIL_FUNC`: $(I `data`) returns one value, a symbolic constant indicating what function is used to compare the stencil reference value with the stencil buffer value. The initial value is `ALWAYS`. See $(REF stencilFunc). This stencil state only affects non-polygons and front-facing polygons. Back-facing polygons use separate stencil state. See $(REF stencilFuncSeparate).
	
	- `STENCIL_PASS_DEPTH_FAIL`: $(I `data`) returns one value, a symbolic constant indicating what action is taken when the stencil test passes, but the depth test fails. The initial value is `KEEP`. See $(REF stencilOp). This stencil state only affects non-polygons and front-facing polygons. Back-facing polygons use separate stencil state. See $(REF stencilOpSeparate).
	
	- `STENCIL_PASS_DEPTH_PASS`: $(I `data`) returns one value, a symbolic constant indicating what action is taken when the stencil test passes and the depth test passes. The initial value is `KEEP`. See $(REF stencilOp). This stencil state only affects non-polygons and front-facing polygons. Back-facing polygons use separate stencil state. See $(REF stencilOpSeparate).
	
	- `STENCIL_REF`: $(I `data`) returns one value, the reference value that is compared with the contents of the stencil buffer. The initial value is 0. See $(REF stencilFunc). This stencil state only affects non-polygons and front-facing polygons. Back-facing polygons use separate stencil state. See $(REF stencilFuncSeparate).
	
	- `STENCIL_TEST`: $(I `data`) returns a single boolean value indicating whether stencil testing of fragments is enabled. The initial value is `FALSE`. See $(REF stencilFunc) and $(REF stencilOp).
	
	- `STENCIL_VALUE_MASK`: $(I `data`) returns one value, the mask that is used to mask both the stencil reference value and the stencil buffer value before they are compared. The initial value is all 1's. See $(REF stencilFunc). This stencil state only affects non-polygons and front-facing polygons. Back-facing polygons use separate stencil state. See $(REF stencilFuncSeparate).
	
	- `STENCIL_WRITEMASK`: $(I `data`) returns one value, the mask that controls writing of the stencil bitplanes. The initial value is all 1's. See $(REF stencilMask). This stencil state only affects non-polygons and front-facing polygons. Back-facing polygons use separate stencil state. See $(REF stencilMaskSeparate).
	
	- `STEREO`: $(I `data`) returns a single boolean value indicating whether stereo buffers (left and right) are supported.
	
	- `SUBPIXEL_BITS`: $(I `data`) returns one value, an estimate of the number of bits of subpixel resolution that are used to position rasterized geometry in window coordinates. The value must be at least 4.
	
	- `TEXTURE_BINDING_1D`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_1D`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_1D_ARRAY`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_1D_ARRAY`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_2D`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_2D`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_2D_ARRAY`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_2D_ARRAY`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_2D_MULTISAMPLE`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_2D_MULTISAMPLE`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_2D_MULTISAMPLE_ARRAY`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_2D_MULTISAMPLE_ARRAY`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_3D`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_3D`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_BUFFER`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_BUFFER`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_CUBE_MAP`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_CUBE_MAP`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_RECTANGLE`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_RECTANGLE`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_COMPRESSION_HINT`: $(I `data`) returns a single value indicating the mode of the texture compression hint. The initial value is `DONT_CARE`.
	
	- `TEXTURE_BINDING_BUFFER`: $(I `data`) returns a single value, the name of the buffer object currently bound to the `TEXTURE_BUFFER` buffer binding point. The initial value is 0. See $(REF bindBuffer).
	
	- `TEXTURE_BUFFER_OFFSET_ALIGNMENT`: $(I `data`) returns a single value, the minimum required alignment for texture buffer sizes and offset. The initial value is 1. See $(REF uniformBlockBinding).
	
	- `TIMESTAMP`: $(I `data`) returns a single value, the 64-bit value of the current GL time. See $(REF queryCounter).
	
	- `TRANSFORM_FEEDBACK_BUFFER_BINDING`: When used with non-indexed variants of $(REF get) (such as $(REF getIntegerv)), $(I `data`) returns a single value, the name of the buffer object currently bound to the target `TRANSFORM_FEEDBACK_BUFFER`. If no buffer object is bound to this target, 0 is returned. When used with indexed variants of $(REF get) (such as $(REF getIntegeri_v)), $(I `data`) returns a single value, the name of the buffer object bound to the indexed transform feedback attribute stream. The initial value is 0 for all targets. See $(REF bindBuffer), $(REF bindBufferBase), and $(REF bindBufferRange).
	
	- `TRANSFORM_FEEDBACK_BUFFER_START`: When used with indexed variants of $(REF get) (such as $(REF getInteger64i_v)), $(I `data`) returns a single value, the start offset of the binding range for each transform feedback attribute stream. The initial value is 0 for all streams. See $(REF bindBufferRange).
	
	- `TRANSFORM_FEEDBACK_BUFFER_SIZE`: When used with indexed variants of $(REF get) (such as $(REF getInteger64i_v)), $(I `data`) returns a single value, the size of the binding range for each transform feedback attribute stream. The initial value is 0 for all streams. See $(REF bindBufferRange).
	
	- `UNIFORM_BUFFER_BINDING`: When used with non-indexed variants of $(REF get) (such as $(REF getIntegerv)), $(I `data`) returns a single value, the name of the buffer object currently bound to the target `UNIFORM_BUFFER`. If no buffer object is bound to this target, 0 is returned. When used with indexed variants of $(REF get) (such as $(REF getIntegeri_v)), $(I `data`) returns a single value, the name of the buffer object bound to the indexed uniform buffer binding point. The initial value is 0 for all targets. See $(REF bindBuffer), $(REF bindBufferBase), and $(REF bindBufferRange).
	
	- `UNIFORM_BUFFER_OFFSET_ALIGNMENT`: $(I `data`) returns a single value, the minimum required alignment for uniform buffer sizes and offset. The initial value is 1. See $(REF uniformBlockBinding).
	
	- `UNIFORM_BUFFER_SIZE`: When used with indexed variants of $(REF get) (such as $(REF getInteger64i_v)), $(I `data`) returns a single value, the size of the binding range for each indexed uniform buffer binding. The initial value is 0 for all bindings. See $(REF bindBufferRange).
	
	- `UNIFORM_BUFFER_START`: When used with indexed variants of $(REF get) (such as $(REF getInteger64i_v)), $(I `data`) returns a single value, the start offset of the binding range for each indexed uniform buffer binding. The initial value is 0 for all bindings. See $(REF bindBufferRange).
	
	- `UNPACK_ALIGNMENT`: $(I `data`) returns one value, the byte alignment used for reading pixel data from memory. The initial value is 4. See $(REF pixelStore).
	
	- `UNPACK_IMAGE_HEIGHT`: $(I `data`) returns one value, the image height used for reading pixel data from memory. The initial is 0. See $(REF pixelStore).
	
	- `UNPACK_LSB_FIRST`: $(I `data`) returns a single boolean value indicating whether single-bit pixels being read from memory are read first from the least significant bit of each unsigned byte. The initial value is `FALSE`. See $(REF pixelStore).
	
	- `UNPACK_ROW_LENGTH`: $(I `data`) returns one value, the row length used for reading pixel data from memory. The initial value is 0. See $(REF pixelStore).
	
	- `UNPACK_SKIP_IMAGES`: $(I `data`) returns one value, the number of pixel images skipped before the first pixel is read from memory. The initial value is 0. See $(REF pixelStore).
	
	- `UNPACK_SKIP_PIXELS`: $(I `data`) returns one value, the number of pixel locations skipped before the first pixel is read from memory. The initial value is 0. See $(REF pixelStore).
	
	- `UNPACK_SKIP_ROWS`: $(I `data`) returns one value, the number of rows of pixel locations skipped before the first pixel is read from memory. The initial value is 0. See $(REF pixelStore).
	
	- `UNPACK_SWAP_BYTES`: $(I `data`) returns a single boolean value indicating whether the bytes of two-byte and four-byte pixel indices and components are swapped after being read from memory. The initial value is `FALSE`. See $(REF pixelStore).
	
	- `VERTEX_ARRAY_BINDING`: $(I `data`) returns a single value, the name of the vertex array object currently bound to the context. If no vertex array object is bound to the context, 0 is returned. The initial value is 0. See $(REF bindVertexArray).
	
	- `VERTEX_BINDING_DIVISOR`: Accepted by the indexed forms. $(I `data`) returns a single integer value representing the instance step divisor of the first element in the bound buffer's data store for vertex attribute bound to $(I `index`).
	
	- `VERTEX_BINDING_OFFSET`: Accepted by the indexed forms. $(I `data`) returns a single integer value representing the byte offset of the first element in the bound buffer's data store for vertex attribute bound to $(I `index`).
	
	- `VERTEX_BINDING_STRIDE`: Accepted by the indexed forms. $(I `data`) returns a single integer value representing the byte offset between the start of each element in the bound buffer's data store for vertex attribute bound to $(I `index`).
	
	- `VERTEX_BINDING_BUFFER`: Accepted by the indexed forms. $(I `data`) returns a single integer value representing the name of the buffer bound to vertex binding $(I `index`).
	
	- `MAX_VERTEX_ATTRIB_RELATIVE_OFFSET`: $(I `data`) returns a single integer value containing the maximum offset that may be added to a vertex binding offset.
	
	- `MAX_VERTEX_ATTRIB_BINDINGS`: $(I `data`) returns a single integer value containing the maximum number of vertex buffers that may be bound.
	
	- `VIEWPORT`: When used with non-indexed variants of $(REF get) (such as $(REF getIntegerv)), $(I `data`) returns four values: the x and y window coordinates of the viewport, followed by its width and height. Initially the x and y window coordinates are both set to 0, and the width and height are set to the width and height of the window into which the GL will do its rendering. See $(REF viewport).   When used with indexed variants of $(REF get) (such as $(REF getIntegeri_v)), $(I `data`) returns four values: the x and y window coordinates of the indexed viewport, followed by its width and height. Initially the x and y window coordinates are both set to 0, and the width and height are set to the width and height of the window into which the GL will do its rendering. See $(REF viewportIndexedf).
	
	- `VIEWPORT_BOUNDS_RANGE`: $(I `data`) returns two values, the minimum and maximum viewport bounds range. The minimum range should be at least [-32768, 32767].
	
	- `VIEWPORT_INDEX_PROVOKING_VERTEX`: $(I `data`) returns one value, the implementation dependent specifc vertex of a primitive that is used to select the viewport index. If the value returned is equivalent to `PROVOKING_VERTEX`, then the vertex selection follows the convention specified by $(REF provokingVertex). If the value returned is equivalent to `FIRST_VERTEX_CONVENTION`, then the selection is always taken from the first vertex in the primitive. If the value returned is equivalent to `LAST_VERTEX_CONVENTION`, then the selection is always taken from the last vertex in the primitive. If the value returned is equivalent to `UNDEFINED_VERTEX`, then the selection is not guaranteed to be taken from any specific vertex in the primitive.
	
	- `VIEWPORT_SUBPIXEL_BITS`: $(I `data`) returns a single value, the number of bits of sub-pixel precision which the GL uses to interpret the floating point viewport bounds. The minimum value is 0.
	
	- `MAX_ELEMENT_INDEX`: $(I `data`) returns a single value, the maximum index that may be specified during the transfer of generic vertex attributes to the GL.
	
	Many of the boolean parameters can also be queried more easily using $(REF isEnabled).
	
	Params:
	pname = Specifies the parameter value to be returned for non-indexed versions of $(REF get). The symbolic constants in the list below are accepted.
	data = Returns the value or values of the specified parameter.
	*/
	void getFloatv(Enum pname, Float* data);
	
	/**
	These commands return values for simple state variables in GL. $(I `pname`) is a symbolic constant indicating the state variable to be returned, and $(I `data`) is a pointer to an array of the indicated type in which to place the returned data.
	
	Type conversion is performed if $(I `data`) has a different type than the state variable value being requested. If $(REF getBooleanv) is called, a floating-point (or integer) value is converted to `FALSE` if and only if it is 0.0 (or 0). Otherwise, it is converted to `TRUE`. If $(REF getIntegerv) is called, boolean values are returned as `TRUE` or `FALSE`, and most floating-point values are rounded to the nearest integer value. Floating-point colors and normals, however, are returned with a linear mapping that maps 1.0 to the most positive representable integer value and -1.0 to the most negative representable integer value. If $(REF getFloatv) or $(REF getDoublev) is called, boolean values are returned as `TRUE` or `FALSE`, and integer values are converted to floating-point values.
	
	The following symbolic constants are accepted by $(I `pname`):
	
	- `ACTIVE_TEXTURE`: $(I `data`) returns a single value indicating the active multitexture unit. The initial value is `TEXTURE0`. See $(REF activeTexture).
	
	- `ALIASED_LINE_WIDTH_RANGE`: $(I `data`) returns a pair of values indicating the range of widths supported for aliased lines. See $(REF lineWidth).
	
	- `ARRAY_BUFFER_BINDING`: $(I `data`) returns a single value, the name of the buffer object currently bound to the target `ARRAY_BUFFER`. If no buffer object is bound to this target, 0 is returned. The initial value is 0. See $(REF bindBuffer).
	
	- `BLEND`: $(I `data`) returns a single boolean value indicating whether blending is enabled. The initial value is `FALSE`. See $(REF blendFunc).
	
	- `BLEND_COLOR`: $(I `data`) returns four values, the red, green, blue, and alpha values which are the components of the blend color. See $(REF blendColor).
	
	- `BLEND_DST_ALPHA`: $(I `data`) returns one value, the symbolic constant identifying the alpha destination blend function. The initial value is `ZERO`. See $(REF blendFunc) and $(REF blendFuncSeparate).
	
	- `BLEND_DST_RGB`: $(I `data`) returns one value, the symbolic constant identifying the RGB destination blend function. The initial value is `ZERO`. See $(REF blendFunc) and $(REF blendFuncSeparate).
	
	- `BLEND_EQUATION_RGB`: $(I `data`) returns one value, a symbolic constant indicating whether the RGB blend equation is `FUNC_ADD`, `FUNC_SUBTRACT`, `FUNC_REVERSE_SUBTRACT`, `MIN` or `MAX`. See $(REF blendEquationSeparate).
	
	- `BLEND_EQUATION_ALPHA`: $(I `data`) returns one value, a symbolic constant indicating whether the Alpha blend equation is `FUNC_ADD`, `FUNC_SUBTRACT`, `FUNC_REVERSE_SUBTRACT`, `MIN` or `MAX`. See $(REF blendEquationSeparate).
	
	- `BLEND_SRC_ALPHA`: $(I `data`) returns one value, the symbolic constant identifying the alpha source blend function. The initial value is `ONE`. See $(REF blendFunc) and $(REF blendFuncSeparate).
	
	- `BLEND_SRC_RGB`: $(I `data`) returns one value, the symbolic constant identifying the RGB source blend function. The initial value is `ONE`. See $(REF blendFunc) and $(REF blendFuncSeparate).
	
	- `COLOR_CLEAR_VALUE`: $(I `data`) returns four values: the red, green, blue, and alpha values used to clear the color buffers. Integer values, if requested, are linearly mapped from the internal floating-point representation such that 1.0 returns the most positive representable integer value, and  -1.0  returns the most negative representable integer value. The initial value is (0, 0, 0, 0). See $(REF clearColor).
	
	- `COLOR_LOGIC_OP`: $(I `data`) returns a single boolean value indicating whether a fragment's RGBA color values are merged into the framebuffer using a logical operation. The initial value is `FALSE`. See $(REF logicOp).
	
	- `COLOR_WRITEMASK`: $(I `data`) returns four boolean values: the red, green, blue, and alpha write enables for the color buffers. The initial value is (`TRUE`, `TRUE`, `TRUE`, `TRUE`). See $(REF colorMask).
	
	- `COMPRESSED_TEXTURE_FORMATS`: $(I `data`) returns a list of symbolic constants of length `NUM_COMPRESSED_TEXTURE_FORMATS` indicating which compressed texture formats are available. See $(REF compressedTexImage2D).
	
	- `MAX_COMPUTE_SHADER_STORAGE_BLOCKS`: $(I `data`) returns one value, the maximum number of active shader storage blocks that may be accessed by a compute shader.
	
	- `MAX_COMBINED_SHADER_STORAGE_BLOCKS`: $(I `data`) returns one value, the maximum total number of active shader storage blocks that may be accessed by all active shaders.
	
	- `MAX_COMPUTE_UNIFORM_BLOCKS`: $(I `data`) returns one value, the maximum number of uniform blocks per compute shader. The value must be at least 14. See $(REF uniformBlockBinding).
	
	- `MAX_COMPUTE_TEXTURE_IMAGE_UNITS`: $(I `data`) returns one value, the maximum supported texture image units that can be used to access texture maps from the compute shader. The value may be at least 16. See $(REF activeTexture).
	
	- `MAX_COMPUTE_UNIFORM_COMPONENTS`: $(I `data`) returns one value, the maximum number of individual floating-point, integer, or boolean values that can be held in uniform variable storage for a compute shader. The value must be at least 1024. See $(REF uniform).
	
	- `MAX_COMPUTE_ATOMIC_COUNTERS`: $(I `data`) returns a single value, the maximum number of atomic counters available to compute shaders.
	
	- `MAX_COMPUTE_ATOMIC_COUNTER_BUFFERS`: $(I `data`) returns a single value, the maximum number of atomic counter buffers that may be accessed by a compute shader.
	
	- `MAX_COMBINED_COMPUTE_UNIFORM_COMPONENTS`: $(I `data`) returns one value, the number of words for compute shader uniform variables in all uniform blocks (including default). The value must be at least 1. See $(REF uniform).
	
	- `MAX_COMPUTE_WORK_GROUP_INVOCATIONS`: $(I `data`) returns one value, the number of invocations in a single local work group (i.e., the product of the three dimensions) that may be dispatched to a compute shader.
	
	- `MAX_COMPUTE_WORK_GROUP_COUNT`: Accepted by the indexed versions of $(REF get). $(I `data`) the maximum number of work groups that may be dispatched to a compute shader. Indices 0, 1, and 2 correspond to the X, Y and Z dimensions, respectively.
	
	- `MAX_COMPUTE_WORK_GROUP_SIZE`: Accepted by the indexed versions of $(REF get). $(I `data`) the maximum size of a work groups that may be used during compilation of a compute shader. Indices 0, 1, and 2 correspond to the X, Y and Z dimensions, respectively.
	
	- `DISPATCH_INDIRECT_BUFFER_BINDING`: $(I `data`) returns a single value, the name of the buffer object currently bound to the target `DISPATCH_INDIRECT_BUFFER`. If no buffer object is bound to this target, 0 is returned. The initial value is 0. See $(REF bindBuffer).
	
	- `MAX_DEBUG_GROUP_STACK_DEPTH`: $(I `data`) returns a single value, the maximum depth of the debug message group stack.
	
	- `DEBUG_GROUP_STACK_DEPTH`: $(I `data`) returns a single value, the current depth of the debug message group stack.
	
	- `CONTEXT_FLAGS`: $(I `data`) returns one value, the flags with which the context was created (such as debugging functionality).
	
	- `CULL_FACE`: $(I `data`) returns a single boolean value indicating whether polygon culling is enabled. The initial value is `FALSE`. See $(REF cullFace).
	
	- `CULL_FACE_MODE`: $(I `data`) returns a single value indicating the mode of polygon culling. The initial value is `BACK`. See $(REF cullFace).
	
	- `CURRENT_PROGRAM`: $(I `data`) returns one value, the name of the program object that is currently active, or 0 if no program object is active. See $(REF useProgram).
	
	- `DEPTH_CLEAR_VALUE`: $(I `data`) returns one value, the value that is used to clear the depth buffer. Integer values, if requested, are linearly mapped from the internal floating-point representation such that 1.0 returns the most positive representable integer value, and  -1.0  returns the most negative representable integer value. The initial value is 1. See $(REF clearDepth).
	
	- `DEPTH_FUNC`: $(I `data`) returns one value, the symbolic constant that indicates the depth comparison function. The initial value is `LESS`. See $(REF depthFunc).
	
	- `DEPTH_RANGE`: $(I `data`) returns two values: the near and far mapping limits for the depth buffer. Integer values, if requested, are linearly mapped from the internal floating-point representation such that 1.0 returns the most positive representable integer value, and  -1.0  returns the most negative representable integer value. The initial value is (0, 1). See $(REF depthRange).
	
	- `DEPTH_TEST`: $(I `data`) returns a single boolean value indicating whether depth testing of fragments is enabled. The initial value is `FALSE`. See $(REF depthFunc) and $(REF depthRange).
	
	- `DEPTH_WRITEMASK`: $(I `data`) returns a single boolean value indicating if the depth buffer is enabled for writing. The initial value is `TRUE`. See $(REF depthMask).
	
	- `DITHER`: $(I `data`) returns a single boolean value indicating whether dithering of fragment colors and indices is enabled. The initial value is `TRUE`.
	
	- `DOUBLEBUFFER`: $(I `data`) returns a single boolean value indicating whether double buffering is supported.
	
	- `DRAW_BUFFER`: $(I `data`) returns one value, a symbolic constant indicating which buffers are being drawn to. See $(REF drawBuffer). The initial value is `BACK` if there are back buffers, otherwise it is `FRONT`.
	
	- `DRAW_BUFFER`  $(I i): $(I `data`) returns one value, a symbolic constant indicating which buffers are being drawn to by the corresponding output color. See $(REF drawBuffers). The initial value of `DRAW_BUFFER0` is `BACK` if there are back buffers, otherwise it is `FRONT`. The initial values of draw buffers for all other output colors is `NONE`.
	
	- `DRAW_FRAMEBUFFER_BINDING`: $(I `data`) returns one value, the name of the framebuffer object currently bound to the `DRAW_FRAMEBUFFER` target. If the default framebuffer is bound, this value will be zero. The initial value is zero. See $(REF bindFramebuffer).
	
	- `READ_FRAMEBUFFER_BINDING`: $(I `data`) returns one value, the name of the framebuffer object currently bound to the `READ_FRAMEBUFFER` target. If the default framebuffer is bound, this value will be zero. The initial value is zero. See $(REF bindFramebuffer).
	
	- `ELEMENT_ARRAY_BUFFER_BINDING`: $(I `data`) returns a single value, the name of the buffer object currently bound to the target `ELEMENT_ARRAY_BUFFER`. If no buffer object is bound to this target, 0 is returned. The initial value is 0. See $(REF bindBuffer).
	
	- `FRAGMENT_SHADER_DERIVATIVE_HINT`: $(I `data`) returns one value, a symbolic constant indicating the mode of the derivative accuracy hint for fragment shaders. The initial value is `DONT_CARE`. See $(REF hint).
	
	- `IMPLEMENTATION_COLOR_READ_FORMAT`: $(I `data`) returns a single GLenum value indicating the implementation's preferred pixel data format. See $(REF readPixels).
	
	- `IMPLEMENTATION_COLOR_READ_TYPE`: $(I `data`) returns a single GLenum value indicating the implementation's preferred pixel data type. See $(REF readPixels).
	
	- `LINE_SMOOTH`: $(I `data`) returns a single boolean value indicating whether antialiasing of lines is enabled. The initial value is `FALSE`. See $(REF lineWidth).
	
	- `LINE_SMOOTH_HINT`: $(I `data`) returns one value, a symbolic constant indicating the mode of the line antialiasing hint. The initial value is `DONT_CARE`. See $(REF hint).
	
	- `LINE_WIDTH`: $(I `data`) returns one value, the line width as specified with $(REF lineWidth). The initial value is 1.
	
	- `LAYER_PROVOKING_VERTEX`: $(I `data`) returns one value, the implementation dependent specifc vertex of a primitive that is used to select the rendering layer. If the value returned is equivalent to `PROVOKING_VERTEX`, then the vertex selection follows the convention specified by $(REF provokingVertex). If the value returned is equivalent to `FIRST_VERTEX_CONVENTION`, then the selection is always taken from the first vertex in the primitive. If the value returned is equivalent to `LAST_VERTEX_CONVENTION`, then the selection is always taken from the last vertex in the primitive. If the value returned is equivalent to `UNDEFINED_VERTEX`, then the selection is not guaranteed to be taken from any specific vertex in the primitive.
	
	- `LOGIC_OP_MODE`: $(I `data`) returns one value, a symbolic constant indicating the selected logic operation mode. The initial value is `COPY`. See $(REF logicOp).
	
	- `MAJOR_VERSION`: $(I `data`) returns one value, the major version number of the OpenGL API supported by the current context.
	
	- `MAX_3D_TEXTURE_SIZE`: $(I `data`) returns one value, a rough estimate of the largest 3D texture that the GL can handle. The value must be at least 64. Use `PROXY_TEXTURE_3D` to determine if a texture is too large. See $(REF texImage3D).
	
	- `MAX_ARRAY_TEXTURE_LAYERS`: $(I `data`) returns one value. The value indicates the maximum number of layers allowed in an array texture, and must be at least 256. See $(REF texImage2D).
	
	- `MAX_CLIP_DISTANCES`: $(I `data`) returns one value, the maximum number of application-defined clipping distances. The value must be at least 8.
	
	- `MAX_COLOR_TEXTURE_SAMPLES`: $(I `data`) returns one value, the maximum number of samples in a color multisample texture.
	
	- `MAX_COMBINED_ATOMIC_COUNTERS`: $(I `data`) returns a single value, the maximum number of atomic counters available to all active shaders.
	
	- `MAX_COMBINED_FRAGMENT_UNIFORM_COMPONENTS`: $(I `data`) returns one value, the number of words for fragment shader uniform variables in all uniform blocks (including default). The value must be at least 1. See $(REF uniform).
	
	- `MAX_COMBINED_GEOMETRY_UNIFORM_COMPONENTS`: $(I `data`) returns one value, the number of words for geometry shader uniform variables in all uniform blocks (including default). The value must be at least 1. See $(REF uniform).
	
	- `MAX_COMBINED_TEXTURE_IMAGE_UNITS`: $(I `data`) returns one value, the maximum supported texture image units that can be used to access texture maps from the vertex shader and the fragment processor combined. If both the vertex shader and the fragment processing stage access the same texture image unit, then that counts as using two texture image units against this limit. The value must be at least 48. See $(REF activeTexture).
	
	- `MAX_COMBINED_UNIFORM_BLOCKS`: $(I `data`) returns one value, the maximum number of uniform blocks per program. The value must be at least 70. See $(REF uniformBlockBinding).
	
	- `MAX_COMBINED_VERTEX_UNIFORM_COMPONENTS`: $(I `data`) returns one value, the number of words for vertex shader uniform variables in all uniform blocks (including default). The value must be at least 1. See $(REF uniform).
	
	- `MAX_CUBE_MAP_TEXTURE_SIZE`: $(I `data`) returns one value. The value gives a rough estimate of the largest cube-map texture that the GL can handle. The value must be at least 1024. Use `PROXY_TEXTURE_CUBE_MAP` to determine if a texture is too large. See $(REF texImage2D).
	
	- `MAX_DEPTH_TEXTURE_SAMPLES`: $(I `data`) returns one value, the maximum number of samples in a multisample depth or depth-stencil texture.
	
	- `MAX_DRAW_BUFFERS`: $(I `data`) returns one value, the maximum number of simultaneous outputs that may be written in a fragment shader. The value must be at least 8. See $(REF drawBuffers).
	
	- `MAX_DUAL_SOURCE_DRAW_BUFFERS`: $(I `data`) returns one value, the maximum number of active draw buffers when using dual-source blending. The value must be at least 1. See $(REF blendFunc) and $(REF blendFuncSeparate).
	
	- `MAX_ELEMENTS_INDICES`: $(I `data`) returns one value, the recommended maximum number of vertex array indices. See $(REF drawRangeElements).
	
	- `MAX_ELEMENTS_VERTICES`: $(I `data`) returns one value, the recommended maximum number of vertex array vertices. See $(REF drawRangeElements).
	
	- `MAX_FRAGMENT_ATOMIC_COUNTERS`: $(I `data`) returns a single value, the maximum number of atomic counters available to fragment shaders.
	
	- `MAX_FRAGMENT_SHADER_STORAGE_BLOCKS`: $(I `data`) returns one value, the maximum number of active shader storage blocks that may be accessed by a fragment shader.
	
	- `MAX_FRAGMENT_INPUT_COMPONENTS`: $(I `data`) returns one value, the maximum number of components of the inputs read by the fragment shader, which must be at least 128.
	
	- `MAX_FRAGMENT_UNIFORM_COMPONENTS`: $(I `data`) returns one value, the maximum number of individual floating-point, integer, or boolean values that can be held in uniform variable storage for a fragment shader. The value must be at least 1024. See $(REF uniform).
	
	- `MAX_FRAGMENT_UNIFORM_VECTORS`: $(I `data`) returns one value, the maximum number of individual 4-vectors of floating-point, integer, or boolean values that can be held in uniform variable storage for a fragment shader. The value is equal to the value of `MAX_FRAGMENT_UNIFORM_COMPONENTS` divided by 4 and must be at least 256. See $(REF uniform).
	
	- `MAX_FRAGMENT_UNIFORM_BLOCKS`: $(I `data`) returns one value, the maximum number of uniform blocks per fragment shader. The value must be at least 12. See $(REF uniformBlockBinding).
	
	- `MAX_FRAMEBUFFER_WIDTH`: $(I `data`) returns one value, the maximum width for a framebuffer that has no attachments, which must be at least 16384. See $(REF framebufferParameter).
	
	- `MAX_FRAMEBUFFER_HEIGHT`: $(I `data`) returns one value, the maximum height for a framebuffer that has no attachments, which must be at least 16384. See $(REF framebufferParameter).
	
	- `MAX_FRAMEBUFFER_LAYERS`: $(I `data`) returns one value, the maximum number of layers for a framebuffer that has no attachments, which must be at least 2048. See $(REF framebufferParameter).
	
	- `MAX_FRAMEBUFFER_SAMPLES`: $(I `data`) returns one value, the maximum samples in a framebuffer that has no attachments, which must be at least 4. See $(REF framebufferParameter).
	
	- `MAX_GEOMETRY_ATOMIC_COUNTERS`: $(I `data`) returns a single value, the maximum number of atomic counters available to geometry shaders.
	
	- `MAX_GEOMETRY_SHADER_STORAGE_BLOCKS`: $(I `data`) returns one value, the maximum number of active shader storage blocks that may be accessed by a geometry shader.
	
	- `MAX_GEOMETRY_INPUT_COMPONENTS`: $(I `data`) returns one value, the maximum number of components of inputs read by a geometry shader, which must be at least 64.
	
	- `MAX_GEOMETRY_OUTPUT_COMPONENTS`: $(I `data`) returns one value, the maximum number of components of outputs written by a geometry shader, which must be at least 128.
	
	- `MAX_GEOMETRY_TEXTURE_IMAGE_UNITS`: $(I `data`) returns one value, the maximum supported texture image units that can be used to access texture maps from the geometry shader. The value must be at least 16. See $(REF activeTexture).
	
	- `MAX_GEOMETRY_UNIFORM_BLOCKS`: $(I `data`) returns one value, the maximum number of uniform blocks per geometry shader. The value must be at least 12. See $(REF uniformBlockBinding).
	
	- `MAX_GEOMETRY_UNIFORM_COMPONENTS`: $(I `data`) returns one value, the maximum number of individual floating-point, integer, or boolean values that can be held in uniform variable storage for a geometry shader. The value must be at least 1024. See $(REF uniform).
	
	- `MAX_INTEGER_SAMPLES`: $(I `data`) returns one value, the maximum number of samples supported in integer format multisample buffers.
	
	- `MIN_MAP_BUFFER_ALIGNMENT`: $(I `data`) returns one value, the minimum alignment in basic machine units of pointers returned from$(REF mapBuffer) and $(REF mapBufferRange). This value must be a power of two and must be at least 64.
	
	- `MAX_LABEL_LENGTH`: $(I `data`) returns one value, the maximum length of a label that may be assigned to an object. See $(REF objectLabel) and $(REF objectPtrLabel).
	
	- `MAX_PROGRAM_TEXEL_OFFSET`: $(I `data`) returns one value, the maximum texel offset allowed in a texture lookup, which must be at least 7.
	
	- `MIN_PROGRAM_TEXEL_OFFSET`: $(I `data`) returns one value, the minimum texel offset allowed in a texture lookup, which must be at most -8.
	
	- `MAX_RECTANGLE_TEXTURE_SIZE`: $(I `data`) returns one value. The value gives a rough estimate of the largest rectangular texture that the GL can handle. The value must be at least 1024. Use `PROXY_TEXTURE_RECTANGLE` to determine if a texture is too large. See $(REF texImage2D).
	
	- `MAX_RENDERBUFFER_SIZE`: $(I `data`) returns one value. The value indicates the maximum supported size for renderbuffers. See $(REF framebufferRenderbuffer).
	
	- `MAX_SAMPLE_MASK_WORDS`: $(I `data`) returns one value, the maximum number of sample mask words.
	
	- `MAX_SERVER_WAIT_TIMEOUT`: $(I `data`) returns one value, the maximum $(REF waitSync) timeout interval.
	
	- `MAX_SHADER_STORAGE_BUFFER_BINDINGS`: $(I `data`) returns one value, the maximum number of shader storage buffer binding points on the context, which must be at least 8.
	
	- `MAX_TESS_CONTROL_ATOMIC_COUNTERS`: $(I `data`) returns a single value, the maximum number of atomic counters available to tessellation control shaders.
	
	- `MAX_TESS_EVALUATION_ATOMIC_COUNTERS`: $(I `data`) returns a single value, the maximum number of atomic counters available to tessellation evaluation shaders.
	
	- `MAX_TESS_CONTROL_SHADER_STORAGE_BLOCKS`: $(I `data`) returns one value, the maximum number of active shader storage blocks that may be accessed by a tessellation control shader.
	
	- `MAX_TESS_EVALUATION_SHADER_STORAGE_BLOCKS`: $(I `data`) returns one value, the maximum number of active shader storage blocks that may be accessed by a tessellation evaluation shader.
	
	- `MAX_TEXTURE_BUFFER_SIZE`: $(I `data`) returns one value. The value gives the maximum number of texels allowed in the texel array of a texture buffer object. Value must be at least 65536.
	
	- `MAX_TEXTURE_IMAGE_UNITS`: $(I `data`) returns one value, the maximum supported texture image units that can be used to access texture maps from the fragment shader. The value must be at least 16. See $(REF activeTexture).
	
	- `MAX_TEXTURE_LOD_BIAS`: $(I `data`) returns one value, the maximum, absolute value of the texture level-of-detail bias. The value must be at least 2.0.
	
	- `MAX_TEXTURE_SIZE`: $(I `data`) returns one value. The value gives a rough estimate of the largest texture that the GL can handle. The value must be at least 1024. Use a proxy texture target such as `PROXY_TEXTURE_1D` or `PROXY_TEXTURE_2D` to determine if a texture is too large. See $(REF texImage1D) and $(REF texImage2D).
	
	- `MAX_UNIFORM_BUFFER_BINDINGS`: $(I `data`) returns one value, the maximum number of uniform buffer binding points on the context, which must be at least 36.
	
	- `MAX_UNIFORM_BLOCK_SIZE`: $(I `data`) returns one value, the maximum size in basic machine units of a uniform block, which must be at least 16384.
	
	- `MAX_UNIFORM_LOCATIONS`: $(I `data`) returns one value, the maximum number of explicitly assignable uniform locations, which must be at least 1024.
	
	- `MAX_VARYING_COMPONENTS`: $(I `data`) returns one value, the number components for varying variables, which must be at least 60.
	
	- `MAX_VARYING_VECTORS`: $(I `data`) returns one value, the number 4-vectors for varying variables, which is equal to the value of `MAX_VARYING_COMPONENTS` and must be at least 15.
	
	- `MAX_VARYING_FLOATS`: $(I `data`) returns one value, the maximum number of interpolators available for processing varying variables used by vertex and fragment shaders. This value represents the number of individual floating-point values that can be interpolated; varying variables declared as vectors, matrices, and arrays will all consume multiple interpolators. The value must be at least 32.
	
	- `MAX_VERTEX_ATOMIC_COUNTERS`: $(I `data`) returns a single value, the maximum number of atomic counters available to vertex shaders.
	
	- `MAX_VERTEX_ATTRIBS`: $(I `data`) returns one value, the maximum number of 4-component generic vertex attributes accessible to a vertex shader. The value must be at least 16. See $(REF vertexAttrib).
	
	- `MAX_VERTEX_SHADER_STORAGE_BLOCKS`: $(I `data`) returns one value, the maximum number of active shader storage blocks that may be accessed by a vertex shader.
	
	- `MAX_VERTEX_TEXTURE_IMAGE_UNITS`: $(I `data`) returns one value, the maximum supported texture image units that can be used to access texture maps from the vertex shader. The value may be at least 16. See $(REF activeTexture).
	
	- `MAX_VERTEX_UNIFORM_COMPONENTS`: $(I `data`) returns one value, the maximum number of individual floating-point, integer, or boolean values that can be held in uniform variable storage for a vertex shader. The value must be at least 1024. See $(REF uniform).
	
	- `MAX_VERTEX_UNIFORM_VECTORS`: $(I `data`) returns one value, the maximum number of 4-vectors that may be held in uniform variable storage for the vertex shader. The value of `MAX_VERTEX_UNIFORM_VECTORS` is equal to the value of `MAX_VERTEX_UNIFORM_COMPONENTS` and must be at least 256.
	
	- `MAX_VERTEX_OUTPUT_COMPONENTS`: $(I `data`) returns one value, the maximum number of components of output written by a vertex shader, which must be at least 64.
	
	- `MAX_VERTEX_UNIFORM_BLOCKS`: $(I `data`) returns one value, the maximum number of uniform blocks per vertex shader. The value must be at least 12. See $(REF uniformBlockBinding).
	
	- `MAX_VIEWPORT_DIMS`: $(I `data`) returns two values: the maximum supported width and height of the viewport. These must be at least as large as the visible dimensions of the display being rendered to. See $(REF viewport).
	
	- `MAX_VIEWPORTS`: $(I `data`) returns one value, the maximum number of simultaneous viewports that are supported. The value must be at least 16. See $(REF viewportIndexed).
	
	- `MINOR_VERSION`: $(I `data`) returns one value, the minor version number of the OpenGL API supported by the current context.
	
	- `NUM_COMPRESSED_TEXTURE_FORMATS`: $(I `data`) returns a single integer value indicating the number of available compressed texture formats. The minimum value is 4. See $(REF compressedTexImage2D).
	
	- `NUM_EXTENSIONS`: $(I `data`) returns one value, the number of extensions supported by the GL implementation for the current context. See $(REF getString).
	
	- `NUM_PROGRAM_BINARY_FORMATS`: $(I `data`) returns one value, the number of program binary formats supported by the implementation.
	
	- `NUM_SHADER_BINARY_FORMATS`: $(I `data`) returns one value, the number of binary shader formats supported by the implementation. If this value is greater than zero, then the implementation supports loading binary shaders. If it is zero, then the loading of binary shaders by the implementation is not supported.
	
	- `PACK_ALIGNMENT`: $(I `data`) returns one value, the byte alignment used for writing pixel data to memory. The initial value is 4. See $(REF pixelStore).
	
	- `PACK_IMAGE_HEIGHT`: $(I `data`) returns one value, the image height used for writing pixel data to memory. The initial value is 0. See $(REF pixelStore).
	
	- `PACK_LSB_FIRST`: $(I `data`) returns a single boolean value indicating whether single-bit pixels being written to memory are written first to the least significant bit of each unsigned byte. The initial value is `FALSE`. See $(REF pixelStore).
	
	- `PACK_ROW_LENGTH`: $(I `data`) returns one value, the row length used for writing pixel data to memory. The initial value is 0. See $(REF pixelStore).
	
	- `PACK_SKIP_IMAGES`: $(I `data`) returns one value, the number of pixel images skipped before the first pixel is written into memory. The initial value is 0. See $(REF pixelStore).
	
	- `PACK_SKIP_PIXELS`: $(I `data`) returns one value, the number of pixel locations skipped before the first pixel is written into memory. The initial value is 0. See $(REF pixelStore).
	
	- `PACK_SKIP_ROWS`: $(I `data`) returns one value, the number of rows of pixel locations skipped before the first pixel is written into memory. The initial value is 0. See $(REF pixelStore).
	
	- `PACK_SWAP_BYTES`: $(I `data`) returns a single boolean value indicating whether the bytes of two-byte and four-byte pixel indices and components are swapped before being written to memory. The initial value is `FALSE`. See $(REF pixelStore).
	
	- `PIXEL_PACK_BUFFER_BINDING`: $(I `data`) returns a single value, the name of the buffer object currently bound to the target `PIXEL_PACK_BUFFER`. If no buffer object is bound to this target, 0 is returned. The initial value is 0. See $(REF bindBuffer).
	
	- `PIXEL_UNPACK_BUFFER_BINDING`: $(I `data`) returns a single value, the name of the buffer object currently bound to the target `PIXEL_UNPACK_BUFFER`. If no buffer object is bound to this target, 0 is returned. The initial value is 0. See $(REF bindBuffer).
	
	- `POINT_FADE_THRESHOLD_SIZE`: $(I `data`) returns one value, the point size threshold for determining the point size. See $(REF pointParameter).
	
	- `PRIMITIVE_RESTART_INDEX`: $(I `data`) returns one value, the current primitive restart index. The initial value is 0. See $(REF primitiveRestartIndex).
	
	- `PROGRAM_BINARY_FORMATS`: $(I `data`) an array of `NUM_PROGRAM_BINARY_FORMATS` values, indicating the proram binary formats supported by the implementation.
	
	- `PROGRAM_PIPELINE_BINDING`: $(I `data`) a single value, the name of the currently bound program pipeline object, or zero if no program pipeline object is bound. See $(REF bindProgramPipeline).
	
	- `PROGRAM_POINT_SIZE`: $(I `data`) returns a single boolean value indicating whether vertex program point size mode is enabled. If enabled, then the point size is taken from the shader built-in `gl_PointSize`. If disabled, then the point size is taken from the point state as specified by $(REF pointSize). The initial value is `FALSE`.
	
	- `PROVOKING_VERTEX`: $(I `data`) returns one value, the currently selected provoking vertex convention. The initial value is `LAST_VERTEX_CONVENTION`. See $(REF provokingVertex).
	
	- `POINT_SIZE`: $(I `data`) returns one value, the point size as specified by $(REF pointSize). The initial value is 1.
	
	- `POINT_SIZE_GRANULARITY`: $(I `data`) returns one value, the size difference between adjacent supported sizes for antialiased points. See $(REF pointSize).
	
	- `POINT_SIZE_RANGE`: $(I `data`) returns two values: the smallest and largest supported sizes for antialiased points. The smallest size must be at most 1, and the largest size must be at least 1. See $(REF pointSize).
	
	- `POLYGON_OFFSET_FACTOR`: $(I `data`) returns one value, the scaling factor used to determine the variable offset that is added to the depth value of each fragment generated when a polygon is rasterized. The initial value is 0. See $(REF polygonOffset).
	
	- `POLYGON_OFFSET_UNITS`: $(I `data`) returns one value. This value is multiplied by an implementation-specific value and then added to the depth value of each fragment generated when a polygon is rasterized. The initial value is 0. See $(REF polygonOffset).
	
	- `POLYGON_OFFSET_FILL`: $(I `data`) returns a single boolean value indicating whether polygon offset is enabled for polygons in fill mode. The initial value is `FALSE`. See $(REF polygonOffset).
	
	- `POLYGON_OFFSET_LINE`: $(I `data`) returns a single boolean value indicating whether polygon offset is enabled for polygons in line mode. The initial value is `FALSE`. See $(REF polygonOffset).
	
	- `POLYGON_OFFSET_POINT`: $(I `data`) returns a single boolean value indicating whether polygon offset is enabled for polygons in point mode. The initial value is `FALSE`. See $(REF polygonOffset).
	
	- `POLYGON_SMOOTH`: $(I `data`) returns a single boolean value indicating whether antialiasing of polygons is enabled. The initial value is `FALSE`. See $(REF polygonMode).
	
	- `POLYGON_SMOOTH_HINT`: $(I `data`) returns one value, a symbolic constant indicating the mode of the polygon antialiasing hint. The initial value is `DONT_CARE`. See $(REF hint).
	
	- `READ_BUFFER`: $(I `data`) returns one value, a symbolic constant indicating which color buffer is selected for reading. The initial value is `BACK` if there is a back buffer, otherwise it is `FRONT`. See $(REF readPixels).
	
	- `RENDERBUFFER_BINDING`: $(I `data`) returns a single value, the name of the renderbuffer object currently bound to the target `RENDERBUFFER`. If no renderbuffer object is bound to this target, 0 is returned. The initial value is 0. See $(REF bindRenderbuffer).
	
	- `SAMPLE_BUFFERS`: $(I `data`) returns a single integer value indicating the number of sample buffers associated with the framebuffer. See $(REF sampleCoverage).
	
	- `SAMPLE_COVERAGE_VALUE`: $(I `data`) returns a single positive floating-point value indicating the current sample coverage value. See $(REF sampleCoverage).
	
	- `SAMPLE_COVERAGE_INVERT`: $(I `data`) returns a single boolean value indicating if the temporary coverage value should be inverted. See $(REF sampleCoverage).
	
	- `SAMPLER_BINDING`: $(I `data`) returns a single value, the name of the sampler object currently bound to the active texture unit. The initial value is 0. See $(REF bindSampler).
	
	- `SAMPLES`: $(I `data`) returns a single integer value indicating the coverage mask size. See $(REF sampleCoverage).
	
	- `SCISSOR_BOX`: $(I `data`) returns four values: the x and y window coordinates of the scissor box, followed by its width and height. Initially the x and y window coordinates are both 0 and the width and height are set to the size of the window. See $(REF scissor).
	
	- `SCISSOR_TEST`: $(I `data`) returns a single boolean value indicating whether scissoring is enabled. The initial value is `FALSE`. See $(REF scissor).
	
	- `SHADER_COMPILER`: $(I `data`) returns a single boolean value indicating whether an online shader compiler is present in the implementation. All desktop OpenGL implementations must support online shader compilations, and therefore the value of `SHADER_COMPILER` will always be `TRUE`.
	
	- `SHADER_STORAGE_BUFFER_BINDING`: When used with non-indexed variants of $(REF get) (such as $(REF getIntegerv)), $(I `data`) returns a single value, the name of the buffer object currently bound to the target `SHADER_STORAGE_BUFFER`. If no buffer object is bound to this target, 0 is returned. When used with indexed variants of $(REF get) (such as $(REF getIntegeri_v)), $(I `data`) returns a single value, the name of the buffer object bound to the indexed shader storage buffer binding points. The initial value is 0 for all targets. See $(REF bindBuffer), $(REF bindBufferBase), and $(REF bindBufferRange).
	
	- `SHADER_STORAGE_BUFFER_OFFSET_ALIGNMENT`: $(I `data`) returns a single value, the minimum required alignment for shader storage buffer sizes and offset. The initial value is 1. See $(REF shaderStorageBlockBinding).
	
	- `SHADER_STORAGE_BUFFER_START`: When used with indexed variants of $(REF get) (such as $(REF getInteger64i_v)), $(I `data`) returns a single value, the start offset of the binding range for each indexed shader storage buffer binding. The initial value is 0 for all bindings. See $(REF bindBufferRange).
	
	- `SHADER_STORAGE_BUFFER_SIZE`: When used with indexed variants of $(REF get) (such as $(REF getInteger64i_v)), $(I `data`) returns a single value, the size of the binding range for each indexed shader storage buffer binding. The initial value is 0 for all bindings. See $(REF bindBufferRange).
	
	- `SMOOTH_LINE_WIDTH_RANGE`: $(I `data`) returns a pair of values indicating the range of widths supported for smooth (antialiased) lines. See $(REF lineWidth).
	
	- `SMOOTH_LINE_WIDTH_GRANULARITY`: $(I `data`) returns a single value indicating the level of quantization applied to smooth line width parameters.
	
	- `STENCIL_BACK_FAIL`: $(I `data`) returns one value, a symbolic constant indicating what action is taken for back-facing polygons when the stencil test fails. The initial value is `KEEP`. See $(REF stencilOpSeparate).
	
	- `STENCIL_BACK_FUNC`: $(I `data`) returns one value, a symbolic constant indicating what function is used for back-facing polygons to compare the stencil reference value with the stencil buffer value. The initial value is `ALWAYS`. See $(REF stencilFuncSeparate).
	
	- `STENCIL_BACK_PASS_DEPTH_FAIL`: $(I `data`) returns one value, a symbolic constant indicating what action is taken for back-facing polygons when the stencil test passes, but the depth test fails. The initial value is `KEEP`. See $(REF stencilOpSeparate).
	
	- `STENCIL_BACK_PASS_DEPTH_PASS`: $(I `data`) returns one value, a symbolic constant indicating what action is taken for back-facing polygons when the stencil test passes and the depth test passes. The initial value is `KEEP`. See $(REF stencilOpSeparate).
	
	- `STENCIL_BACK_REF`: $(I `data`) returns one value, the reference value that is compared with the contents of the stencil buffer for back-facing polygons. The initial value is 0. See $(REF stencilFuncSeparate).
	
	- `STENCIL_BACK_VALUE_MASK`: $(I `data`) returns one value, the mask that is used for back-facing polygons to mask both the stencil reference value and the stencil buffer value before they are compared. The initial value is all 1's. See $(REF stencilFuncSeparate).
	
	- `STENCIL_BACK_WRITEMASK`: $(I `data`) returns one value, the mask that controls writing of the stencil bitplanes for back-facing polygons. The initial value is all 1's. See $(REF stencilMaskSeparate).
	
	- `STENCIL_CLEAR_VALUE`: $(I `data`) returns one value, the index to which the stencil bitplanes are cleared. The initial value is 0. See $(REF clearStencil).
	
	- `STENCIL_FAIL`: $(I `data`) returns one value, a symbolic constant indicating what action is taken when the stencil test fails. The initial value is `KEEP`. See $(REF stencilOp). This stencil state only affects non-polygons and front-facing polygons. Back-facing polygons use separate stencil state. See $(REF stencilOpSeparate).
	
	- `STENCIL_FUNC`: $(I `data`) returns one value, a symbolic constant indicating what function is used to compare the stencil reference value with the stencil buffer value. The initial value is `ALWAYS`. See $(REF stencilFunc). This stencil state only affects non-polygons and front-facing polygons. Back-facing polygons use separate stencil state. See $(REF stencilFuncSeparate).
	
	- `STENCIL_PASS_DEPTH_FAIL`: $(I `data`) returns one value, a symbolic constant indicating what action is taken when the stencil test passes, but the depth test fails. The initial value is `KEEP`. See $(REF stencilOp). This stencil state only affects non-polygons and front-facing polygons. Back-facing polygons use separate stencil state. See $(REF stencilOpSeparate).
	
	- `STENCIL_PASS_DEPTH_PASS`: $(I `data`) returns one value, a symbolic constant indicating what action is taken when the stencil test passes and the depth test passes. The initial value is `KEEP`. See $(REF stencilOp). This stencil state only affects non-polygons and front-facing polygons. Back-facing polygons use separate stencil state. See $(REF stencilOpSeparate).
	
	- `STENCIL_REF`: $(I `data`) returns one value, the reference value that is compared with the contents of the stencil buffer. The initial value is 0. See $(REF stencilFunc). This stencil state only affects non-polygons and front-facing polygons. Back-facing polygons use separate stencil state. See $(REF stencilFuncSeparate).
	
	- `STENCIL_TEST`: $(I `data`) returns a single boolean value indicating whether stencil testing of fragments is enabled. The initial value is `FALSE`. See $(REF stencilFunc) and $(REF stencilOp).
	
	- `STENCIL_VALUE_MASK`: $(I `data`) returns one value, the mask that is used to mask both the stencil reference value and the stencil buffer value before they are compared. The initial value is all 1's. See $(REF stencilFunc). This stencil state only affects non-polygons and front-facing polygons. Back-facing polygons use separate stencil state. See $(REF stencilFuncSeparate).
	
	- `STENCIL_WRITEMASK`: $(I `data`) returns one value, the mask that controls writing of the stencil bitplanes. The initial value is all 1's. See $(REF stencilMask). This stencil state only affects non-polygons and front-facing polygons. Back-facing polygons use separate stencil state. See $(REF stencilMaskSeparate).
	
	- `STEREO`: $(I `data`) returns a single boolean value indicating whether stereo buffers (left and right) are supported.
	
	- `SUBPIXEL_BITS`: $(I `data`) returns one value, an estimate of the number of bits of subpixel resolution that are used to position rasterized geometry in window coordinates. The value must be at least 4.
	
	- `TEXTURE_BINDING_1D`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_1D`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_1D_ARRAY`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_1D_ARRAY`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_2D`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_2D`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_2D_ARRAY`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_2D_ARRAY`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_2D_MULTISAMPLE`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_2D_MULTISAMPLE`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_2D_MULTISAMPLE_ARRAY`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_2D_MULTISAMPLE_ARRAY`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_3D`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_3D`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_BUFFER`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_BUFFER`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_CUBE_MAP`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_CUBE_MAP`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_BINDING_RECTANGLE`: $(I `data`) returns a single value, the name of the texture currently bound to the target `TEXTURE_RECTANGLE`. The initial value is 0. See $(REF bindTexture).
	
	- `TEXTURE_COMPRESSION_HINT`: $(I `data`) returns a single value indicating the mode of the texture compression hint. The initial value is `DONT_CARE`.
	
	- `TEXTURE_BINDING_BUFFER`: $(I `data`) returns a single value, the name of the buffer object currently bound to the `TEXTURE_BUFFER` buffer binding point. The initial value is 0. See $(REF bindBuffer).
	
	- `TEXTURE_BUFFER_OFFSET_ALIGNMENT`: $(I `data`) returns a single value, the minimum required alignment for texture buffer sizes and offset. The initial value is 1. See $(REF uniformBlockBinding).
	
	- `TIMESTAMP`: $(I `data`) returns a single value, the 64-bit value of the current GL time. See $(REF queryCounter).
	
	- `TRANSFORM_FEEDBACK_BUFFER_BINDING`: When used with non-indexed variants of $(REF get) (such as $(REF getIntegerv)), $(I `data`) returns a single value, the name of the buffer object currently bound to the target `TRANSFORM_FEEDBACK_BUFFER`. If no buffer object is bound to this target, 0 is returned. When used with indexed variants of $(REF get) (such as $(REF getIntegeri_v)), $(I `data`) returns a single value, the name of the buffer object bound to the indexed transform feedback attribute stream. The initial value is 0 for all targets. See $(REF bindBuffer), $(REF bindBufferBase), and $(REF bindBufferRange).
	
	- `TRANSFORM_FEEDBACK_BUFFER_START`: When used with indexed variants of $(REF get) (such as $(REF getInteger64i_v)), $(I `data`) returns a single value, the start offset of the binding range for each transform feedback attribute stream. The initial value is 0 for all streams. See $(REF bindBufferRange).
	
	- `TRANSFORM_FEEDBACK_BUFFER_SIZE`: When used with indexed variants of $(REF get) (such as $(REF getInteger64i_v)), $(I `data`) returns a single value, the size of the binding range for each transform feedback attribute stream. The initial value is 0 for all streams. See $(REF bindBufferRange).
	
	- `UNIFORM_BUFFER_BINDING`: When used with non-indexed variants of $(REF get) (such as $(REF getIntegerv)), $(I `data`) returns a single value, the name of the buffer object currently bound to the target `UNIFORM_BUFFER`. If no buffer object is bound to this target, 0 is returned. When used with indexed variants of $(REF get) (such as $(REF getIntegeri_v)), $(I `data`) returns a single value, the name of the buffer object bound to the indexed uniform buffer binding point. The initial value is 0 for all targets. See $(REF bindBuffer), $(REF bindBufferBase), and $(REF bindBufferRange).
	
	- `UNIFORM_BUFFER_OFFSET_ALIGNMENT`: $(I `data`) returns a single value, the minimum required alignment for uniform buffer sizes and offset. The initial value is 1. See $(REF uniformBlockBinding).
	
	- `UNIFORM_BUFFER_SIZE`: When used with indexed variants of $(REF get) (such as $(REF getInteger64i_v)), $(I `data`) returns a single value, the size of the binding range for each indexed uniform buffer binding. The initial value is 0 for all bindings. See $(REF bindBufferRange).
	
	- `UNIFORM_BUFFER_START`: When used with indexed variants of $(REF get) (such as $(REF getInteger64i_v)), $(I `data`) returns a single value, the start offset of the binding range for each indexed uniform buffer binding. The initial value is 0 for all bindings. See $(REF bindBufferRange).
	
	- `UNPACK_ALIGNMENT`: $(I `data`) returns one value, the byte alignment used for reading pixel data from memory. The initial value is 4. See $(REF pixelStore).
	
	- `UNPACK_IMAGE_HEIGHT`: $(I `data`) returns one value, the image height used for reading pixel data from memory. The initial is 0. See $(REF pixelStore).
	
	- `UNPACK_LSB_FIRST`: $(I `data`) returns a single boolean value indicating whether single-bit pixels being read from memory are read first from the least significant bit of each unsigned byte. The initial value is `FALSE`. See $(REF pixelStore).
	
	- `UNPACK_ROW_LENGTH`: $(I `data`) returns one value, the row length used for reading pixel data from memory. The initial value is 0. See $(REF pixelStore).
	
	- `UNPACK_SKIP_IMAGES`: $(I `data`) returns one value, the number of pixel images skipped before the first pixel is read from memory. The initial value is 0. See $(REF pixelStore).
	
	- `UNPACK_SKIP_PIXELS`: $(I `data`) returns one value, the number of pixel locations skipped before the first pixel is read from memory. The initial value is 0. See $(REF pixelStore).
	
	- `UNPACK_SKIP_ROWS`: $(I `data`) returns one value, the number of rows of pixel locations skipped before the first pixel is read from memory. The initial value is 0. See $(REF pixelStore).
	
	- `UNPACK_SWAP_BYTES`: $(I `data`) returns a single boolean value indicating whether the bytes of two-byte and four-byte pixel indices and components are swapped after being read from memory. The initial value is `FALSE`. See $(REF pixelStore).
	
	- `VERTEX_ARRAY_BINDING`: $(I `data`) returns a single value, the name of the vertex array object currently bound to the context. If no vertex array object is bound to the context, 0 is returned. The initial value is 0. See $(REF bindVertexArray).
	
	- `VERTEX_BINDING_DIVISOR`: Accepted by the indexed forms. $(I `data`) returns a single integer value representing the instance step divisor of the first element in the bound buffer's data store for vertex attribute bound to $(I `index`).
	
	- `VERTEX_BINDING_OFFSET`: Accepted by the indexed forms. $(I `data`) returns a single integer value representing the byte offset of the first element in the bound buffer's data store for vertex attribute bound to $(I `index`).
	
	- `VERTEX_BINDING_STRIDE`: Accepted by the indexed forms. $(I `data`) returns a single integer value representing the byte offset between the start of each element in the bound buffer's data store for vertex attribute bound to $(I `index`).
	
	- `VERTEX_BINDING_BUFFER`: Accepted by the indexed forms. $(I `data`) returns a single integer value representing the name of the buffer bound to vertex binding $(I `index`).
	
	- `MAX_VERTEX_ATTRIB_RELATIVE_OFFSET`: $(I `data`) returns a single integer value containing the maximum offset that may be added to a vertex binding offset.
	
	- `MAX_VERTEX_ATTRIB_BINDINGS`: $(I `data`) returns a single integer value containing the maximum number of vertex buffers that may be bound.
	
	- `VIEWPORT`: When used with non-indexed variants of $(REF get) (such as $(REF getIntegerv)), $(I `data`) returns four values: the x and y window coordinates of the viewport, followed by its width and height. Initially the x and y window coordinates are both set to 0, and the width and height are set to the width and height of the window into which the GL will do its rendering. See $(REF viewport).   When used with indexed variants of $(REF get) (such as $(REF getIntegeri_v)), $(I `data`) returns four values: the x and y window coordinates of the indexed viewport, followed by its width and height. Initially the x and y window coordinates are both set to 0, and the width and height are set to the width and height of the window into which the GL will do its rendering. See $(REF viewportIndexedf).
	
	- `VIEWPORT_BOUNDS_RANGE`: $(I `data`) returns two values, the minimum and maximum viewport bounds range. The minimum range should be at least [-32768, 32767].
	
	- `VIEWPORT_INDEX_PROVOKING_VERTEX`: $(I `data`) returns one value, the implementation dependent specifc vertex of a primitive that is used to select the viewport index. If the value returned is equivalent to `PROVOKING_VERTEX`, then the vertex selection follows the convention specified by $(REF provokingVertex). If the value returned is equivalent to `FIRST_VERTEX_CONVENTION`, then the selection is always taken from the first vertex in the primitive. If the value returned is equivalent to `LAST_VERTEX_CONVENTION`, then the selection is always taken from the last vertex in the primitive. If the value returned is equivalent to `UNDEFINED_VERTEX`, then the selection is not guaranteed to be taken from any specific vertex in the primitive.
	
	- `VIEWPORT_SUBPIXEL_BITS`: $(I `data`) returns a single value, the number of bits of sub-pixel precision which the GL uses to interpret the floating point viewport bounds. The minimum value is 0.
	
	- `MAX_ELEMENT_INDEX`: $(I `data`) returns a single value, the maximum index that may be specified during the transfer of generic vertex attributes to the GL.
	
	Many of the boolean parameters can also be queried more easily using $(REF isEnabled).
	
	Params:
	pname = Specifies the parameter value to be returned for non-indexed versions of $(REF get). The symbolic constants in the list below are accepted.
	data = Returns the value or values of the specified parameter.
	*/
	void getIntegerv(Enum pname, Int* data);
	
	/**
	$(REF getString) returns a pointer to a static string describing some aspect of the current GL connection. $(I `name`) can be one of the following:
	
	- `VENDOR`: Returns the company responsible for this GL implementation. This name does not change from release to release.
	
	- `RENDERER`: Returns the name of the renderer. This name is typically specific to a particular configuration of a hardware platform. It does not change from release to release.
	
	- `VERSION`: Returns a version or release number.
	
	- `SHADING_LANGUAGE_VERSION`: Returns a version or release number for the shading language.
	
	$(REF getStringi) returns a pointer to a static string indexed by $(I `index`). $(I `name`) can be one of the following:
	
	- `EXTENSIONS`: For $(REF getStringi) only, returns the extension string supported by the implementation at $(I `index`).
	
	Strings `VENDOR` and `RENDERER` together uniquely specify a platform. They do not change from release to release and should be used by platform-recognition algorithms.
	
	The `VERSION` and `SHADING_LANGUAGE_VERSION` strings begin with a version number. The version number uses one of these forms:
	
	$(I major_number.minor_number) $(I major_number.minor_number.release_number)
	
	Vendor-specific information may follow the version number. Its format depends on the implementation, but a space always separates the version number and the vendor-specific information.
	
	All strings are null-terminated.
	
	Params:
	name = Specifies a symbolic constant, one of `VENDOR`, `RENDERER`, `VERSION`, or `SHADING_LANGUAGE_VERSION`. Additionally, $(REF getStringi) accepts the `EXTENSIONS` token.
	*/
	const(UByte*) getString(Enum name);
	
	/**
	$(REF getTexImage), $(REF getnTexImage) and $(REF getTextureImage) functions return a texture image into $(I `pixels`). For $(REF getTexImage) and $(REF getnTexImage), $(I `target`) specifies whether the desired texture image is one specified by $(REF texImage1D) (`TEXTURE_1D`), $(REF texImage2D) (`TEXTURE_1D_ARRAY`, `TEXTURE_RECTANGLE`, `TEXTURE_2D` or any of `TEXTURE_CUBE_MAP_*`), or $(REF texImage3D) (`TEXTURE_2D_ARRAY`, `TEXTURE_3D`, `TEXTURE_CUBE_MAP_ARRAY`). For $(REF getTextureImage), $(I `texture`) specifies the texture object name. In addition to types of textures accepted by $(REF getTexImage) and $(REF getnTexImage), the function also accepts cube map texture objects (with effective target `TEXTURE_CUBE_MAP`). $(I `level`) specifies the level-of-detail number of the desired image. $(I `format`) and $(I `type`) specify the format and type of the desired image array. See the reference page for $(REF texImage1D) for a description of the acceptable values for the $(I `format`) and $(I `type`) parameters, respectively. For glGetnTexImage and glGetTextureImage functions, bufSize tells the size of the buffer to receive the retrieved pixel data. $(REF getnTexImage) and $(REF getTextureImage) do not write more than $(I `bufSize`) bytes into $(I `pixels`).
	
	If a non-zero named buffer object is bound to the `PIXEL_PACK_BUFFER` target (see $(REF bindBuffer)) while a texture image is requested, $(I `pixels`) is treated as a byte offset into the buffer object's data store.
	
	To understand the operation of $(REF getTexImage), consider the selected internal four-component texture image to be an RGBA color buffer the size of the image. The semantics of $(REF getTexImage) are then identical to those of $(REF readPixels), with the exception that no pixel transfer operations are performed, when called with the same $(I `format`) and $(I `type`), with $(I x) and $(I y) set to 0, $(I width) set to the width of the texture image and $(I height) set to 1 for 1D images, or to the height of the texture image for 2D images.
	
	If the selected texture image does not contain four components, the following mappings are applied. Single-component textures are treated as RGBA buffers with red set to the single-component value, green set to 0, blue set to 0, and alpha set to 1. Two-component textures are treated as RGBA buffers with red set to the value of component zero, alpha set to the value of component one, and green and blue set to 0. Finally, three-component textures are treated as RGBA buffers with red set to component zero, green set to component one, blue set to component two, and alpha set to 1.
	
	To determine the required size of $(I `pixels`), use $(REF getTexLevelParameter) to determine the dimensions of the internal texture image, then scale the required number of pixels by the storage required for each pixel, based on $(I `format`) and $(I `type`). Be sure to take the pixel storage parameters into account, especially `PACK_ALIGNMENT`.
	
	If $(REF getTextureImage) is used against a cube map texture object, the texture is treated as a three-dimensional image of a depth of 6, where the cube map faces are ordered as image layers, in an order presented in the table below:
	
	Params:
	target = Specifies the target to which the texture is bound for $(REF getTexImage) and $(REF getnTexImage) functions. `TEXTURE_1D`, `TEXTURE_2D`, `TEXTURE_3D`, `TEXTURE_1D_ARRAY`, `TEXTURE_2D_ARRAY`, `TEXTURE_RECTANGLE`, `TEXTURE_CUBE_MAP_POSITIVE_X`, `TEXTURE_CUBE_MAP_NEGATIVE_X`, `TEXTURE_CUBE_MAP_POSITIVE_Y`, `TEXTURE_CUBE_MAP_NEGATIVE_Y`, `TEXTURE_CUBE_MAP_POSITIVE_Z`, `TEXTURE_CUBE_MAP_NEGATIVE_Z`, and `TEXTURE_CUBE_MAP_ARRAY` are acceptable.
	level = Specifies the level-of-detail number of the desired image. Level 0 is the base image level. Level n is the nth mipmap reduction image.
	format = Specifies a pixel format for the returned data. The supported formats are `STENCIL_INDEX`, `DEPTH_COMPONENT`, `DEPTH_STENCIL`, `RED`, `GREEN`, `BLUE`, `RG`, `RGB`, `RGBA`, `BGR`, `BGRA`, `RED_INTEGER`, `GREEN_INTEGER`, `BLUE_INTEGER`, `RG_INTEGER`, `RGB_INTEGER`, `RGBA_INTEGER`, `BGR_INTEGER`, `BGRA_INTEGER`.
	type = Specifies a pixel type for the returned data. The supported types are `UNSIGNED_BYTE`, `BYTE`, `UNSIGNED_SHORT`, `SHORT`, `UNSIGNED_INT`, `INT`, `HALF_FLOAT`, `FLOAT`, `UNSIGNED_BYTE_3_3_2`, `UNSIGNED_BYTE_2_3_3_REV`, `UNSIGNED_SHORT_5_6_5`, `UNSIGNED_SHORT_5_6_5_REV`, `UNSIGNED_SHORT_4_4_4_4`, `UNSIGNED_SHORT_4_4_4_4_REV`, `UNSIGNED_SHORT_5_5_5_1`, `UNSIGNED_SHORT_1_5_5_5_REV`, `UNSIGNED_INT_8_8_8_8`, `UNSIGNED_INT_8_8_8_8_REV`, `UNSIGNED_INT_10_10_10_2`, `UNSIGNED_INT_2_10_10_10_REV`, `UNSIGNED_INT_24_8`, `UNSIGNED_INT_10F_11F_11F_REV`, `UNSIGNED_INT_5_9_9_9_REV`, and `FLOAT_32_UNSIGNED_INT_24_8_REV`.
	pixels = Returns the texture image. Should be a pointer to an array of the type specified by $(I `type`).
	*/
	void getTexImage(Enum target, Int level, Enum format, Enum type, void* pixels);
	
	/**
	$(REF getTexParameter) and $(REF getTextureParameter) return in $(I `params`) the value or values of the texture parameter specified as $(I `pname`). $(I `target`) defines the target texture. `TEXTURE_1D`, `TEXTURE_2D`, `TEXTURE_3D`, `TEXTURE_1D_ARRAY`, `TEXTURE_2D_ARRAY`, `TEXTURE_RECTANGLE`, `TEXTURE_CUBE_MAP`, `TEXTURE_CUBE_MAP_ARRAY`, `TEXTURE_2D_MULTISAMPLE`, or `TEXTURE_2D_MULTISAMPLE_ARRAY` specify one-, two-, or three-dimensional, one-dimensional array, two-dimensional array, rectangle, cube-mapped or cube-mapped array, two-dimensional multisample, or two-dimensional multisample array texturing, respectively. $(I `pname`) accepts the same symbols as $(REF texParameter), with the same interpretations:
	
	- `DEPTH_STENCIL_TEXTURE_MODE`: Returns the single-value depth stencil texture mode, a symbolic constant. The initial value is `DEPTH_COMPONENT`.
	
	- `TEXTURE_MAG_FILTER`: Returns the single-valued texture magnification filter, a symbolic constant. The initial value is `LINEAR`.
	
	- `TEXTURE_MIN_FILTER`: Returns the single-valued texture minification filter, a symbolic constant. The initial value is `NEAREST_MIPMAP_LINEAR`.
	
	- `TEXTURE_MIN_LOD`: Returns the single-valued texture minimum level-of-detail value. The initial value is  -1000 .
	
	- `TEXTURE_MAX_LOD`: Returns the single-valued texture maximum level-of-detail value. The initial value is 1000.
	
	- `TEXTURE_BASE_LEVEL`: Returns the single-valued base texture mipmap level. The initial value is 0.
	
	- `TEXTURE_MAX_LEVEL`: Returns the single-valued maximum texture mipmap array level. The initial value is 1000.
	
	- `TEXTURE_SWIZZLE_R`: Returns the red component swizzle. The initial value is `RED`.
	
	- `TEXTURE_SWIZZLE_G`: Returns the green component swizzle. The initial value is `GREEN`.
	
	- `TEXTURE_SWIZZLE_B`: Returns the blue component swizzle. The initial value is `BLUE`.
	
	- `TEXTURE_SWIZZLE_A`: Returns the alpha component swizzle. The initial value is `ALPHA`.
	
	- `TEXTURE_SWIZZLE_RGBA`: Returns the component swizzle for all channels in a single query.
	
	- `TEXTURE_WRAP_S`: Returns the single-valued wrapping function for texture coordinate s, a symbolic constant. The initial value is `REPEAT`.
	
	- `TEXTURE_WRAP_T`: Returns the single-valued wrapping function for texture coordinate t, a symbolic constant. The initial value is `REPEAT`.
	
	- `TEXTURE_WRAP_R`: Returns the single-valued wrapping function for texture coordinate r, a symbolic constant. The initial value is `REPEAT`.
	
	- `TEXTURE_BORDER_COLOR`: Returns four integer or floating-point numbers that comprise the RGBA color of the texture border. Floating-point values are returned in the range   0 1  . Integer values are returned as a linear mapping of the internal floating-point representation such that 1.0 maps to the most positive representable integer and  -1.0  maps to the most negative representable integer. The initial value is (0, 0, 0, 0).
	
	- `TEXTURE_COMPARE_MODE`: Returns a single-valued texture comparison mode, a symbolic constant. The initial value is `NONE`. See $(REF texParameter).
	
	- `TEXTURE_COMPARE_FUNC`: Returns a single-valued texture comparison function, a symbolic constant. The initial value is `LEQUAL`. See $(REF texParameter).
	
	- `TEXTURE_VIEW_MIN_LEVEL`: Returns a single-valued base level of a texture view relative to its parent. The initial value is 0. See $(REF textureView).
	
	- `TEXTURE_VIEW_NUM_LEVELS`: Returns a single-valued number of levels of detail of a texture view. See $(REF textureView).
	
	- `TEXTURE_VIEW_MIN_LAYER`: Returns a single-valued first level of a texture array view relative to its parent. See $(REF textureView).
	
	- `TEXTURE_VIEW_NUM_LAYERS`: Returns a single-valued number of layers in a texture array view. See $(REF textureView).
	
	- `TEXTURE_IMMUTABLE_LEVELS`: Returns a single-valued number of immutable texture levels in a texture view. See $(REF textureView).
	
	In addition to the parameters that may be set with $(REF texParameter), $(REF getTexParameter) and $(REF getTextureParameter) accept the following read-only parameters:
	
	- `IMAGE_FORMAT_COMPATIBILITY_TYPE`: Returns the matching criteria use for the texture when used as an image texture. Can return `IMAGE_FORMAT_COMPATIBILITY_BY_SIZE`, `IMAGE_FORMAT_COMPATIBILITY_BY_CLASS` or `NONE`.
	
	- `TEXTURE_IMMUTABLE_FORMAT`: Returns non-zero if the texture has an immutable format. Textures become immutable if their storage is specified with $(REF texStorage1D), $(REF texStorage2D) or $(REF texStorage3D). The initial value is `FALSE`.
	
	- `TEXTURE_TARGET`: Returns the effective target of the texture object. For $(REF getTex*Parameter) functions, this is the target parameter. For $(REF getTextureParameter*), it is the target to which the texture was initially bound when it was created, or the value of the target parameter to the call to $(REF createTextures) which created the texture.
	
	Params:
	target = Specifies the target to which the texture is bound for $(REF getTexParameterfv), $(REF getTexParameteriv), $(REF getTexParameterIiv), and $(REF getTexParameterIuiv) functions. `TEXTURE_1D`, `TEXTURE_1D_ARRAY`, `TEXTURE_2D`, `TEXTURE_2D_ARRAY`, `TEXTURE_2D_MULTISAMPLE`, `TEXTURE_2D_MULTISAMPLE_ARRAY`, `TEXTURE_3D`, `TEXTURE_CUBE_MAP`, `TEXTURE_RECTANGLE`, and `TEXTURE_CUBE_MAP_ARRAY` are accepted.
	pname = Specifies the symbolic name of a texture parameter. `DEPTH_STENCIL_TEXTURE_MODE`, `IMAGE_FORMAT_COMPATIBILITY_TYPE`, `TEXTURE_BASE_LEVEL`, `TEXTURE_BORDER_COLOR`, `TEXTURE_COMPARE_MODE`, `TEXTURE_COMPARE_FUNC`, `TEXTURE_IMMUTABLE_FORMAT`, `TEXTURE_IMMUTABLE_LEVELS`, `TEXTURE_LOD_BIAS`, `TEXTURE_MAG_FILTER`, `TEXTURE_MAX_LEVEL`, `TEXTURE_MAX_LOD`, `TEXTURE_MIN_FILTER`, `TEXTURE_MIN_LOD`, `TEXTURE_SWIZZLE_R`, `TEXTURE_SWIZZLE_G`, `TEXTURE_SWIZZLE_B`, `TEXTURE_SWIZZLE_A`, `TEXTURE_SWIZZLE_RGBA`, `TEXTURE_TARGET`, `TEXTURE_VIEW_MIN_LAYER`, `TEXTURE_VIEW_MIN_LEVEL`, `TEXTURE_VIEW_NUM_LAYERS`, `TEXTURE_VIEW_NUM_LEVELS`, `TEXTURE_WRAP_S`, `TEXTURE_WRAP_T`, and `TEXTURE_WRAP_R` are accepted.
	params = Returns the texture parameters.
	*/
	void getTexParameterfv(Enum target, Enum pname, Float* params);
	
	/**
	$(REF getTexParameter) and $(REF getTextureParameter) return in $(I `params`) the value or values of the texture parameter specified as $(I `pname`). $(I `target`) defines the target texture. `TEXTURE_1D`, `TEXTURE_2D`, `TEXTURE_3D`, `TEXTURE_1D_ARRAY`, `TEXTURE_2D_ARRAY`, `TEXTURE_RECTANGLE`, `TEXTURE_CUBE_MAP`, `TEXTURE_CUBE_MAP_ARRAY`, `TEXTURE_2D_MULTISAMPLE`, or `TEXTURE_2D_MULTISAMPLE_ARRAY` specify one-, two-, or three-dimensional, one-dimensional array, two-dimensional array, rectangle, cube-mapped or cube-mapped array, two-dimensional multisample, or two-dimensional multisample array texturing, respectively. $(I `pname`) accepts the same symbols as $(REF texParameter), with the same interpretations:
	
	- `DEPTH_STENCIL_TEXTURE_MODE`: Returns the single-value depth stencil texture mode, a symbolic constant. The initial value is `DEPTH_COMPONENT`.
	
	- `TEXTURE_MAG_FILTER`: Returns the single-valued texture magnification filter, a symbolic constant. The initial value is `LINEAR`.
	
	- `TEXTURE_MIN_FILTER`: Returns the single-valued texture minification filter, a symbolic constant. The initial value is `NEAREST_MIPMAP_LINEAR`.
	
	- `TEXTURE_MIN_LOD`: Returns the single-valued texture minimum level-of-detail value. The initial value is  -1000 .
	
	- `TEXTURE_MAX_LOD`: Returns the single-valued texture maximum level-of-detail value. The initial value is 1000.
	
	- `TEXTURE_BASE_LEVEL`: Returns the single-valued base texture mipmap level. The initial value is 0.
	
	- `TEXTURE_MAX_LEVEL`: Returns the single-valued maximum texture mipmap array level. The initial value is 1000.
	
	- `TEXTURE_SWIZZLE_R`: Returns the red component swizzle. The initial value is `RED`.
	
	- `TEXTURE_SWIZZLE_G`: Returns the green component swizzle. The initial value is `GREEN`.
	
	- `TEXTURE_SWIZZLE_B`: Returns the blue component swizzle. The initial value is `BLUE`.
	
	- `TEXTURE_SWIZZLE_A`: Returns the alpha component swizzle. The initial value is `ALPHA`.
	
	- `TEXTURE_SWIZZLE_RGBA`: Returns the component swizzle for all channels in a single query.
	
	- `TEXTURE_WRAP_S`: Returns the single-valued wrapping function for texture coordinate s, a symbolic constant. The initial value is `REPEAT`.
	
	- `TEXTURE_WRAP_T`: Returns the single-valued wrapping function for texture coordinate t, a symbolic constant. The initial value is `REPEAT`.
	
	- `TEXTURE_WRAP_R`: Returns the single-valued wrapping function for texture coordinate r, a symbolic constant. The initial value is `REPEAT`.
	
	- `TEXTURE_BORDER_COLOR`: Returns four integer or floating-point numbers that comprise the RGBA color of the texture border. Floating-point values are returned in the range   0 1  . Integer values are returned as a linear mapping of the internal floating-point representation such that 1.0 maps to the most positive representable integer and  -1.0  maps to the most negative representable integer. The initial value is (0, 0, 0, 0).
	
	- `TEXTURE_COMPARE_MODE`: Returns a single-valued texture comparison mode, a symbolic constant. The initial value is `NONE`. See $(REF texParameter).
	
	- `TEXTURE_COMPARE_FUNC`: Returns a single-valued texture comparison function, a symbolic constant. The initial value is `LEQUAL`. See $(REF texParameter).
	
	- `TEXTURE_VIEW_MIN_LEVEL`: Returns a single-valued base level of a texture view relative to its parent. The initial value is 0. See $(REF textureView).
	
	- `TEXTURE_VIEW_NUM_LEVELS`: Returns a single-valued number of levels of detail of a texture view. See $(REF textureView).
	
	- `TEXTURE_VIEW_MIN_LAYER`: Returns a single-valued first level of a texture array view relative to its parent. See $(REF textureView).
	
	- `TEXTURE_VIEW_NUM_LAYERS`: Returns a single-valued number of layers in a texture array view. See $(REF textureView).
	
	- `TEXTURE_IMMUTABLE_LEVELS`: Returns a single-valued number of immutable texture levels in a texture view. See $(REF textureView).
	
	In addition to the parameters that may be set with $(REF texParameter), $(REF getTexParameter) and $(REF getTextureParameter) accept the following read-only parameters:
	
	- `IMAGE_FORMAT_COMPATIBILITY_TYPE`: Returns the matching criteria use for the texture when used as an image texture. Can return `IMAGE_FORMAT_COMPATIBILITY_BY_SIZE`, `IMAGE_FORMAT_COMPATIBILITY_BY_CLASS` or `NONE`.
	
	- `TEXTURE_IMMUTABLE_FORMAT`: Returns non-zero if the texture has an immutable format. Textures become immutable if their storage is specified with $(REF texStorage1D), $(REF texStorage2D) or $(REF texStorage3D). The initial value is `FALSE`.
	
	- `TEXTURE_TARGET`: Returns the effective target of the texture object. For $(REF getTex*Parameter) functions, this is the target parameter. For $(REF getTextureParameter*), it is the target to which the texture was initially bound when it was created, or the value of the target parameter to the call to $(REF createTextures) which created the texture.
	
	Params:
	target = Specifies the target to which the texture is bound for $(REF getTexParameterfv), $(REF getTexParameteriv), $(REF getTexParameterIiv), and $(REF getTexParameterIuiv) functions. `TEXTURE_1D`, `TEXTURE_1D_ARRAY`, `TEXTURE_2D`, `TEXTURE_2D_ARRAY`, `TEXTURE_2D_MULTISAMPLE`, `TEXTURE_2D_MULTISAMPLE_ARRAY`, `TEXTURE_3D`, `TEXTURE_CUBE_MAP`, `TEXTURE_RECTANGLE`, and `TEXTURE_CUBE_MAP_ARRAY` are accepted.
	pname = Specifies the symbolic name of a texture parameter. `DEPTH_STENCIL_TEXTURE_MODE`, `IMAGE_FORMAT_COMPATIBILITY_TYPE`, `TEXTURE_BASE_LEVEL`, `TEXTURE_BORDER_COLOR`, `TEXTURE_COMPARE_MODE`, `TEXTURE_COMPARE_FUNC`, `TEXTURE_IMMUTABLE_FORMAT`, `TEXTURE_IMMUTABLE_LEVELS`, `TEXTURE_LOD_BIAS`, `TEXTURE_MAG_FILTER`, `TEXTURE_MAX_LEVEL`, `TEXTURE_MAX_LOD`, `TEXTURE_MIN_FILTER`, `TEXTURE_MIN_LOD`, `TEXTURE_SWIZZLE_R`, `TEXTURE_SWIZZLE_G`, `TEXTURE_SWIZZLE_B`, `TEXTURE_SWIZZLE_A`, `TEXTURE_SWIZZLE_RGBA`, `TEXTURE_TARGET`, `TEXTURE_VIEW_MIN_LAYER`, `TEXTURE_VIEW_MIN_LEVEL`, `TEXTURE_VIEW_NUM_LAYERS`, `TEXTURE_VIEW_NUM_LEVELS`, `TEXTURE_WRAP_S`, `TEXTURE_WRAP_T`, and `TEXTURE_WRAP_R` are accepted.
	params = Returns the texture parameters.
	*/
	void getTexParameteriv(Enum target, Enum pname, Int* params);
	
	/**
	$(REF getTexLevelParameterfv), $(REF getTexLevelParameteriv), $(REF getTextureLevelParameterfv) and $(REF getTextureLevelParameteriv) return in $(I `params`) texture parameter values for a specific level-of-detail value, specified as $(I `level`). For the first two functions, $(I `target`) defines the target texture, either `TEXTURE_1D`, `TEXTURE_2D`, `TEXTURE_3D`, `PROXY_TEXTURE_1D`, `PROXY_TEXTURE_2D`, `PROXY_TEXTURE_3D`, `TEXTURE_CUBE_MAP_POSITIVE_X`, `TEXTURE_CUBE_MAP_NEGATIVE_X`, `TEXTURE_CUBE_MAP_POSITIVE_Y`, `TEXTURE_CUBE_MAP_NEGATIVE_Y`, `TEXTURE_CUBE_MAP_POSITIVE_Z`, `TEXTURE_CUBE_MAP_NEGATIVE_Z`, or `PROXY_TEXTURE_CUBE_MAP`. The remaining two take a $(I `texture`) argument which specifies the name of the texture object.
	
	`MAX_TEXTURE_SIZE`, and `MAX_3D_TEXTURE_SIZE` are not really descriptive enough. It has to report the largest square texture image that can be accommodated with mipmaps but a long skinny texture, or a texture without mipmaps may easily fit in texture memory. The proxy targets allow the user to more accurately query whether the GL can accommodate a texture of a given configuration. If the texture cannot be accommodated, the texture state variables, which may be queried with $(REF getTexLevelParameter) and $(REF getTextureLevelParameter), are set to 0. If the texture can be accommodated, the texture state values will be set as they would be set for a non-proxy target.
	
	$(I `pname`) specifies the texture parameter whose value or values will be returned.
	
	The accepted parameter names are as follows:
	
	- `TEXTURE_WIDTH`: $(I `params`) returns a single value, the width of the texture image. The initial value is 0.
	
	- `TEXTURE_HEIGHT`: $(I `params`) returns a single value, the height of the texture image. The initial value is 0.
	
	- `TEXTURE_DEPTH`: $(I `params`) returns a single value, the depth of the texture image. The initial value is 0.
	
	- `TEXTURE_INTERNAL_FORMAT`: $(I `params`) returns a single value, the internal format of the texture image.
	
	- `TEXTURE_RED_TYPE`, `TEXTURE_GREEN_TYPE`, `TEXTURE_BLUE_TYPE`, `TEXTURE_ALPHA_TYPE`, `TEXTURE_DEPTH_TYPE`: The data type used to store the component. The types `NONE`, `SIGNED_NORMALIZED`, `UNSIGNED_NORMALIZED`, `FLOAT`, `INT`, and `UNSIGNED_INT` may be returned to indicate signed normalized fixed-point, unsigned normalized fixed-point, floating-point, integer unnormalized, and unsigned integer unnormalized components, respectively.
	
	- `TEXTURE_RED_SIZE`, `TEXTURE_GREEN_SIZE`, `TEXTURE_BLUE_SIZE`, `TEXTURE_ALPHA_SIZE`, `TEXTURE_DEPTH_SIZE`: The internal storage resolution of an individual component. The resolution chosen by the GL will be a close match for the resolution requested by the user with the component argument of $(REF texImage1D), $(REF texImage2D), $(REF texImage3D), $(REF copyTexImage1D), and $(REF copyTexImage2D). The initial value is 0.
	
	- `TEXTURE_COMPRESSED`: $(I `params`) returns a single boolean value indicating if the texture image is stored in a compressed internal format. The initiali value is `FALSE`.
	
	- `TEXTURE_COMPRESSED_IMAGE_SIZE`: $(I `params`) returns a single integer value, the number of unsigned bytes of the compressed texture image that would be returned from $(REF getCompressedTexImage).
	
	- `TEXTURE_BUFFER_OFFSET`: $(I `params`) returns a single integer value, the offset into the data store of the buffer bound to a buffer texture. $(REF texBufferRange).
	
	- `TEXTURE_BUFFER_SIZE`: $(I `params`) returns a single integer value, the size of the range of a data store of the buffer bound to a buffer texture. $(REF texBufferRange).
	
	Params:
	target = Specifies the target to which the texture is bound for $(REF getTexLevelParameterfv) and $(REF getTexLevelParameteriv) functions. Must be one of the following values: `TEXTURE_1D`, `TEXTURE_2D`, `TEXTURE_3D`, `TEXTURE_1D_ARRAY`, `TEXTURE_2D_ARRAY`, `TEXTURE_RECTANGLE`, `TEXTURE_2D_MULTISAMPLE`, `TEXTURE_2D_MULTISAMPLE_ARRAY`, `TEXTURE_CUBE_MAP_POSITIVE_X`, `TEXTURE_CUBE_MAP_NEGATIVE_X`, `TEXTURE_CUBE_MAP_POSITIVE_Y`, `TEXTURE_CUBE_MAP_NEGATIVE_Y`, `TEXTURE_CUBE_MAP_POSITIVE_Z`, `TEXTURE_CUBE_MAP_NEGATIVE_Z`, `PROXY_TEXTURE_1D`, `PROXY_TEXTURE_2D`, `PROXY_TEXTURE_3D`, `PROXY_TEXTURE_1D_ARRAY`, `PROXY_TEXTURE_2D_ARRAY`, `PROXY_TEXTURE_RECTANGLE`, `PROXY_TEXTURE_2D_MULTISAMPLE`, `PROXY_TEXTURE_2D_MULTISAMPLE_ARRAY`, `PROXY_TEXTURE_CUBE_MAP`, or `TEXTURE_BUFFER`.
	level = Specifies the level-of-detail number of the desired image. Level 0 is the base image level. Level n is the nth mipmap reduction image.
	pname = Specifies the symbolic name of a texture parameter. `TEXTURE_WIDTH`, `TEXTURE_HEIGHT`, `TEXTURE_DEPTH`, `TEXTURE_INTERNAL_FORMAT`, `TEXTURE_RED_SIZE`, `TEXTURE_GREEN_SIZE`, `TEXTURE_BLUE_SIZE`, `TEXTURE_ALPHA_SIZE`, `TEXTURE_DEPTH_SIZE`, `TEXTURE_COMPRESSED`, `TEXTURE_COMPRESSED_IMAGE_SIZE`, and `TEXTURE_BUFFER_OFFSET` are accepted.
	params = Returns the requested data.
	*/
	void getTexLevelParameterfv(Enum target, Int level, Enum pname, Float* params);
	
	/**
	$(REF getTexLevelParameterfv), $(REF getTexLevelParameteriv), $(REF getTextureLevelParameterfv) and $(REF getTextureLevelParameteriv) return in $(I `params`) texture parameter values for a specific level-of-detail value, specified as $(I `level`). For the first two functions, $(I `target`) defines the target texture, either `TEXTURE_1D`, `TEXTURE_2D`, `TEXTURE_3D`, `PROXY_TEXTURE_1D`, `PROXY_TEXTURE_2D`, `PROXY_TEXTURE_3D`, `TEXTURE_CUBE_MAP_POSITIVE_X`, `TEXTURE_CUBE_MAP_NEGATIVE_X`, `TEXTURE_CUBE_MAP_POSITIVE_Y`, `TEXTURE_CUBE_MAP_NEGATIVE_Y`, `TEXTURE_CUBE_MAP_POSITIVE_Z`, `TEXTURE_CUBE_MAP_NEGATIVE_Z`, or `PROXY_TEXTURE_CUBE_MAP`. The remaining two take a $(I `texture`) argument which specifies the name of the texture object.
	
	`MAX_TEXTURE_SIZE`, and `MAX_3D_TEXTURE_SIZE` are not really descriptive enough. It has to report the largest square texture image that can be accommodated with mipmaps but a long skinny texture, or a texture without mipmaps may easily fit in texture memory. The proxy targets allow the user to more accurately query whether the GL can accommodate a texture of a given configuration. If the texture cannot be accommodated, the texture state variables, which may be queried with $(REF getTexLevelParameter) and $(REF getTextureLevelParameter), are set to 0. If the texture can be accommodated, the texture state values will be set as they would be set for a non-proxy target.
	
	$(I `pname`) specifies the texture parameter whose value or values will be returned.
	
	The accepted parameter names are as follows:
	
	- `TEXTURE_WIDTH`: $(I `params`) returns a single value, the width of the texture image. The initial value is 0.
	
	- `TEXTURE_HEIGHT`: $(I `params`) returns a single value, the height of the texture image. The initial value is 0.
	
	- `TEXTURE_DEPTH`: $(I `params`) returns a single value, the depth of the texture image. The initial value is 0.
	
	- `TEXTURE_INTERNAL_FORMAT`: $(I `params`) returns a single value, the internal format of the texture image.
	
	- `TEXTURE_RED_TYPE`, `TEXTURE_GREEN_TYPE`, `TEXTURE_BLUE_TYPE`, `TEXTURE_ALPHA_TYPE`, `TEXTURE_DEPTH_TYPE`: The data type used to store the component. The types `NONE`, `SIGNED_NORMALIZED`, `UNSIGNED_NORMALIZED`, `FLOAT`, `INT`, and `UNSIGNED_INT` may be returned to indicate signed normalized fixed-point, unsigned normalized fixed-point, floating-point, integer unnormalized, and unsigned integer unnormalized components, respectively.
	
	- `TEXTURE_RED_SIZE`, `TEXTURE_GREEN_SIZE`, `TEXTURE_BLUE_SIZE`, `TEXTURE_ALPHA_SIZE`, `TEXTURE_DEPTH_SIZE`: The internal storage resolution of an individual component. The resolution chosen by the GL will be a close match for the resolution requested by the user with the component argument of $(REF texImage1D), $(REF texImage2D), $(REF texImage3D), $(REF copyTexImage1D), and $(REF copyTexImage2D). The initial value is 0.
	
	- `TEXTURE_COMPRESSED`: $(I `params`) returns a single boolean value indicating if the texture image is stored in a compressed internal format. The initiali value is `FALSE`.
	
	- `TEXTURE_COMPRESSED_IMAGE_SIZE`: $(I `params`) returns a single integer value, the number of unsigned bytes of the compressed texture image that would be returned from $(REF getCompressedTexImage).
	
	- `TEXTURE_BUFFER_OFFSET`: $(I `params`) returns a single integer value, the offset into the data store of the buffer bound to a buffer texture. $(REF texBufferRange).
	
	- `TEXTURE_BUFFER_SIZE`: $(I `params`) returns a single integer value, the size of the range of a data store of the buffer bound to a buffer texture. $(REF texBufferRange).
	
	Params:
	target = Specifies the target to which the texture is bound for $(REF getTexLevelParameterfv) and $(REF getTexLevelParameteriv) functions. Must be one of the following values: `TEXTURE_1D`, `TEXTURE_2D`, `TEXTURE_3D`, `TEXTURE_1D_ARRAY`, `TEXTURE_2D_ARRAY`, `TEXTURE_RECTANGLE`, `TEXTURE_2D_MULTISAMPLE`, `TEXTURE_2D_MULTISAMPLE_ARRAY`, `TEXTURE_CUBE_MAP_POSITIVE_X`, `TEXTURE_CUBE_MAP_NEGATIVE_X`, `TEXTURE_CUBE_MAP_POSITIVE_Y`, `TEXTURE_CUBE_MAP_NEGATIVE_Y`, `TEXTURE_CUBE_MAP_POSITIVE_Z`, `TEXTURE_CUBE_MAP_NEGATIVE_Z`, `PROXY_TEXTURE_1D`, `PROXY_TEXTURE_2D`, `PROXY_TEXTURE_3D`, `PROXY_TEXTURE_1D_ARRAY`, `PROXY_TEXTURE_2D_ARRAY`, `PROXY_TEXTURE_RECTANGLE`, `PROXY_TEXTURE_2D_MULTISAMPLE`, `PROXY_TEXTURE_2D_MULTISAMPLE_ARRAY`, `PROXY_TEXTURE_CUBE_MAP`, or `TEXTURE_BUFFER`.
	level = Specifies the level-of-detail number of the desired image. Level 0 is the base image level. Level n is the nth mipmap reduction image.
	pname = Specifies the symbolic name of a texture parameter. `TEXTURE_WIDTH`, `TEXTURE_HEIGHT`, `TEXTURE_DEPTH`, `TEXTURE_INTERNAL_FORMAT`, `TEXTURE_RED_SIZE`, `TEXTURE_GREEN_SIZE`, `TEXTURE_BLUE_SIZE`, `TEXTURE_ALPHA_SIZE`, `TEXTURE_DEPTH_SIZE`, `TEXTURE_COMPRESSED`, `TEXTURE_COMPRESSED_IMAGE_SIZE`, and `TEXTURE_BUFFER_OFFSET` are accepted.
	params = Returns the requested data.
	*/
	void getTexLevelParameteriv(Enum target, Int level, Enum pname, Int* params);
	
	/**
	$(REF isEnabled) returns `TRUE` if $(I `cap`) is an enabled capability and returns `FALSE` otherwise. Boolean states that are indexed may be tested with $(REF isEnabledi). For $(REF isEnabledi), $(I `index`) specifies the index of the capability to test. $(I `index`) must be between zero and the count of indexed capabilities for $(I `cap`). Initially all capabilities except `DITHER` are disabled; `DITHER` is initially enabled.
	
	The following capabilities are accepted for $(I `cap`):
	
	Params:
	cap = Specifies a symbolic constant indicating a GL capability.
	*/
	Boolean isEnabled(Enum cap);
	
	/**
	After clipping and division by $(I w), depth coordinates range from -1 to 1, corresponding to the near and far clipping planes. $(REF depthRange) specifies a linear mapping of the normalized depth coordinates in this range to window depth coordinates. Regardless of the actual depth buffer implementation, window coordinate depth values are treated as though they range from 0 through 1 (like color components). Thus, the values accepted by $(REF depthRange) are both clamped to this range before they are accepted.
	
	The setting of (0,1) maps the near plane to 0 and the far plane to 1. With this mapping, the depth buffer range is fully utilized.
	
	Params:
	nearVal = Specifies the mapping of the near clipping plane to window coordinates. The initial value is 0.
	farVal = Specifies the mapping of the far clipping plane to window coordinates. The initial value is 1.
	*/
	void depthRange(Double nearVal, Double farVal);
	
	/**
	$(REF viewport) specifies the affine transformation of x and y from normalized device coordinates to window coordinates. Let (xnd, ynd) be normalized device coordinates. Then the window coordinates (xw, yw) are computed as follows:
	
	Viewport width and height are silently clamped to a range that depends on the implementation. To query this range, call $(REF get) with argument `MAX_VIEWPORT_DIMS`.
	
	Params:
	x = Specify the lower left corner of the viewport rectangle, in pixels. The initial value is (0,0).
	y = Specify the lower left corner of the viewport rectangle, in pixels. The initial value is (0,0).
	width = Specify the width and height of the viewport. When a GL context is first attached to a window, $(I `width`) and $(I `height`) are set to the dimensions of that window.
	height = Specify the width and height of the viewport. When a GL context is first attached to a window, $(I `width`) and $(I `height`) are set to the dimensions of that window.
	*/
	void viewport(Int x, Int y, Sizei width, Sizei height);
	
	/**
	$(REF drawArrays) specifies multiple geometric primitives with very few subroutine calls. Instead of calling a GL procedure to pass each individual vertex, normal, texture coordinate, edge flag, or color, you can prespecify separate arrays of vertices, normals, and colors and use them to construct a sequence of primitives with a single call to $(REF drawArrays).
	
	When $(REF drawArrays) is called, it uses $(I `count`) sequential elements from each enabled array to construct a sequence of geometric primitives, beginning with element $(I `first`). $(I `mode`) specifies what kind of primitives are constructed and how the array elements construct those primitives.
	
	Vertex attributes that are modified by $(REF drawArrays) have an unspecified value after $(REF drawArrays) returns. Attributes that aren't modified remain well defined.
	
	Params:
	mode = Specifies what kind of primitives to render. Symbolic constants `POINTS`, `LINE_STRIP`, `LINE_LOOP`, `LINES`, `LINE_STRIP_ADJACENCY`, `LINES_ADJACENCY`, `TRIANGLE_STRIP`, `TRIANGLE_FAN`, `TRIANGLES`, `TRIANGLE_STRIP_ADJACENCY`, `TRIANGLES_ADJACENCY` and `PATCHES` are accepted.
	first = Specifies the starting index in the enabled arrays.
	count = Specifies the number of indices to be rendered.
	*/
	void drawArrays(Enum mode, Int first, Sizei count);
	
	/**
	$(REF drawElements) specifies multiple geometric primitives with very few subroutine calls. Instead of calling a GL function to pass each individual vertex, normal, texture coordinate, edge flag, or color, you can prespecify separate arrays of vertices, normals, and so on, and use them to construct a sequence of primitives with a single call to $(REF drawElements).
	
	When $(REF drawElements) is called, it uses $(I `count`) sequential elements from an enabled array, starting at $(I `indices`) to construct a sequence of geometric primitives. $(I `mode`) specifies what kind of primitives are constructed and how the array elements construct these primitives. If more than one array is enabled, each is used.
	
	Vertex attributes that are modified by $(REF drawElements) have an unspecified value after $(REF drawElements) returns. Attributes that aren't modified maintain their previous values.
	
	Params:
	mode = Specifies what kind of primitives to render. Symbolic constants `POINTS`, `LINE_STRIP`, `LINE_LOOP`, `LINES`, `LINE_STRIP_ADJACENCY`, `LINES_ADJACENCY`, `TRIANGLE_STRIP`, `TRIANGLE_FAN`, `TRIANGLES`, `TRIANGLE_STRIP_ADJACENCY`, `TRIANGLES_ADJACENCY` and `PATCHES` are accepted.
	count = Specifies the number of elements to be rendered.
	type = Specifies the type of the values in $(I `indices`). Must be one of `UNSIGNED_BYTE`, `UNSIGNED_SHORT`, or `UNSIGNED_INT`.
	indices = Specifies a pointer to the location where the indices are stored.
	*/
	void drawElements(Enum mode, Sizei count, Enum type, const(void)* indices);
	
	/**
	$(REF getPointerv) returns pointer information. $(I `pname`) indicates the pointer to be returned, and $(I `params`) is a pointer to a location in which to place the returned data. The parameters that may be queried include:
	
	- `DEBUG_CALLBACK_FUNCTION`: Returns the current callback function set with the $(I `callback`) argument of $(REF debugMessageCallback).
	
	- `DEBUG_CALLBACK_USER_PARAM`: Returns the user parameter to the current callback function set with the $(I `userParam`) argument of $(REF debugMessageCallback).
	
	Params:
	pname = Specifies the pointer to be returned. Must be one of `DEBUG_CALLBACK_FUNCTION` or `DEBUG_CALLBACK_USER_PARAM`.
	params = Returns the pointer value specified by $(I `pname`).
	*/
	void getPointerv(Enum pname, void* params);
	
	/**
	When `POLYGON_OFFSET_FILL`, `POLYGON_OFFSET_LINE`, or `POLYGON_OFFSET_POINT` is enabled, each fragment's $(I depth) value will be offset after it is interpolated from the $(I depth) values of the appropriate vertices. The value of the offset is factor×DZ + r×units, where DZ is a measurement of the change in depth relative to the screen area of the polygon, and r is the smallest value that is guaranteed to produce a resolvable offset for a given implementation. The offset is added before the depth test is performed and before the value is written into the depth buffer.
	
	$(REF polygonOffset) is useful for rendering hidden-line images, for applying decals to surfaces, and for rendering solids with highlighted edges.
	
	Params:
	factor = Specifies a scale factor that is used to create a variable depth offset for each polygon. The initial value is 0.
	units = Is multiplied by an implementation-specific value to create a constant depth offset. The initial value is 0.
	*/
	void polygonOffset(Float factor, Float units);
	
	/**
	$(REF copyTexImage1D) defines a one-dimensional texture image with pixels from the current `READ_BUFFER`.
	
	The screen-aligned pixel row with left corner at (x, y) and with a length of width defines the texture array at the mipmap level specified by $(I `level`). $(I `internalformat`) specifies the internal format of the texture array.
	
	The pixels in the row are processed exactly as if $(REF readPixels) had been called, but the process stops just before final conversion. At this point all pixel component values are clamped to the range [0, 1] and then converted to the texture's internal format for storage in the texel array.
	
	Pixel ordering is such that lower x screen coordinates correspond to lower texture coordinates.
	
	If any of the pixels within the specified row of the current `READ_BUFFER` are outside the window associated with the current rendering context, then the values obtained for those pixels are undefined.
	
	$(REF copyTexImage1D) defines a one-dimensional texture image with pixels from the current `READ_BUFFER`.
	
	When $(I `internalformat`) is one of the sRGB types, the GL does not automatically convert the source pixels to the sRGB color space. In this case, the $(REF pixelMap) function can be used to accomplish the conversion.
	
	Params:
	target = Specifies the target texture. Must be `TEXTURE_1D`.
	level = Specifies the level-of-detail number. Level 0 is the base image level. Level $(I n) is the $(I n)th mipmap reduction image.
	internalformat = Specifies the internal format of the texture. Must be one of the following symbolic constants: `COMPRESSED_RED`, `COMPRESSED_RG`, `COMPRESSED_RGB`, `COMPRESSED_RGBA`. `COMPRESSED_SRGB`, `COMPRESSED_SRGB_ALPHA`. `DEPTH_COMPONENT`, `DEPTH_COMPONENT16`, `DEPTH_COMPONENT24`, `DEPTH_COMPONENT32`, `STENCIL_INDEX8`, `RED`, `RG`, `RGB`, `R3_G3_B2`, `RGB4`, `RGB5`, `RGB8`, `RGB10`, `RGB12`, `RGB16`, `RGBA`, `RGBA2`, `RGBA4`, `RGB5_A1`, `RGBA8`, `RGB10_A2`, `RGBA12`, `RGBA16`, `SRGB`, `SRGB8`, `SRGB_ALPHA`, or `SRGB8_ALPHA8`.
	x = Specify the window coordinates of the left corner of the row of pixels to be copied.
	y = Specify the window coordinates of the left corner of the row of pixels to be copied.
	width = Specifies the width of the texture image. The height of the texture image is 1.
	border = Must be 0.
	*/
	void copyTexImage1D(Enum target, Int level, Enum internalformat, Int x, Int y, Sizei width, Int border);
	
	/**
	$(REF copyTexImage2D) defines a two-dimensional texture image, or cube-map texture image with pixels from the current `READ_BUFFER`.
	
	The screen-aligned pixel rectangle with lower left corner at ($(I `x`), $(I `y`)) and with a width of width and a height of height defines the texture array at the mipmap level specified by $(I `level`). $(I `internalformat`) specifies the internal format of the texture array.
	
	The pixels in the rectangle are processed exactly as if $(REF readPixels) had been called, but the process stops just before final conversion. At this point all pixel component values are clamped to the range [0, 1] and then converted to the texture's internal format for storage in the texel array.
	
	Pixel ordering is such that lower x and y screen coordinates correspond to lower s and t texture coordinates.
	
	If any of the pixels within the specified rectangle of the current `READ_BUFFER` are outside the window associated with the current rendering context, then the values obtained for those pixels are undefined.
	
	When $(I `internalformat`) is one of the sRGB types, the GL does not automatically convert the source pixels to the sRGB color space. In this case, the $(REF pixelMap) function can be used to accomplish the conversion.
	
	Params:
	target = Specifies the target texture. Must be `TEXTURE_2D`, `TEXTURE_CUBE_MAP_POSITIVE_X`, `TEXTURE_CUBE_MAP_NEGATIVE_X`, `TEXTURE_CUBE_MAP_POSITIVE_Y`, `TEXTURE_CUBE_MAP_NEGATIVE_Y`, `TEXTURE_CUBE_MAP_POSITIVE_Z`, or `TEXTURE_CUBE_MAP_NEGATIVE_Z`.
	level = Specifies the level-of-detail number. Level 0 is the base image level. Level $(I n) is the $(I n)th mipmap reduction image.
	internalformat = Specifies the internal format of the texture. Must be one of the following symbolic constants: `COMPRESSED_RED`, `COMPRESSED_RG`, `COMPRESSED_RGB`, `COMPRESSED_RGBA`. `COMPRESSED_SRGB`, `COMPRESSED_SRGB_ALPHA`. `DEPTH_COMPONENT`, `DEPTH_COMPONENT16`, `DEPTH_COMPONENT24`, `DEPTH_COMPONENT32`, `STENCIL_INDEX8`, `RED`, `RG`, `RGB`, `R3_G3_B2`, `RGB4`, `RGB5`, `RGB8`, `RGB10`, `RGB12`, `RGB16`, `RGBA`, `RGBA2`, `RGBA4`, `RGB5_A1`, `RGBA8`, `RGB10_A2`, `RGBA12`, `RGBA16`, `SRGB`, `SRGB8`, `SRGB_ALPHA`, or `SRGB8_ALPHA8`.
	x = Specify the window coordinates of the lower left corner of the rectangular region of pixels to be copied.
	y = Specify the window coordinates of the lower left corner of the rectangular region of pixels to be copied.
	width = Specifies the width of the texture image.
	height = Specifies the height of the texture image.
	border = Must be 0.
	*/
	void copyTexImage2D(Enum target, Int level, Enum internalformat, Int x, Int y, Sizei width, Sizei height, Int border);
	
	/**
	$(REF copyTexSubImage1D) and $(REF copyTextureSubImage1D) replace a portion of a one-dimensional texture image with pixels from the current `READ_BUFFER` (rather than from main memory, as is the case for $(REF texSubImage1D)). For $(REF copyTexSubImage1D), the texture object that is bound to $(I `target`) will be used for the process. For $(REF copyTextureSubImage1D), $(I `texture`) tells which texture object should be used for the purpose of the call.
	
	The screen-aligned pixel row with left corner at ($(I `x`),\ $(I `y`)), and with length $(I `width`) replaces the portion of the texture array with x indices $(I `xoffset`) through xoffset + width - 1, inclusive. The destination in the texture array may not include any texels outside the texture array as it was originally specified.
	
	The pixels in the row are processed exactly as if $(REF readPixels) had been called, but the process stops just before final conversion. At this point, all pixel component values are clamped to the range [0, 1] and then converted to the texture's internal format for storage in the texel array.
	
	It is not an error to specify a subtexture with zero width, but such a specification has no effect. If any of the pixels within the specified row of the current `READ_BUFFER` are outside the read window associated with the current rendering context, then the values obtained for those pixels are undefined.
	
	No change is made to the $(I internalformat) or $(I width) parameters of the specified texture array or to texel values outside the specified subregion.
	
	Params:
	target = Specifies the target to which the texture object is bound for $(REF copyTexSubImage1D) function. Must be `TEXTURE_1D`.
	level = Specifies the level-of-detail number. Level 0 is the base image level. Level $(I n) is the $(I n)th mipmap reduction image.
	xoffset = Specifies the texel offset within the texture array.
	x = Specify the window coordinates of the left corner of the row of pixels to be copied.
	y = Specify the window coordinates of the left corner of the row of pixels to be copied.
	width = Specifies the width of the texture subimage.
	*/
	void copyTexSubImage1D(Enum target, Int level, Int xoffset, Int x, Int y, Sizei width);
	
	/**
	$(REF copyTexSubImage2D) and $(REF copyTextureSubImage2D) replace a rectangular portion of a two-dimensional texture image, cube-map texture image, rectangular image, or a linear portion of a number of slices of a one-dimensional array texture with pixels from the current `READ_BUFFER` (rather than from main memory, as is the case for $(REF texSubImage2D)).
	
	The screen-aligned pixel rectangle with lower left corner at (x, y) and with width $(I `width`) and height $(I `height`) replaces the portion of the texture array with x indices $(I `xoffset`) through xoffset + width - 1, inclusive, and y indices $(I `yoffset`) through yoffset + height - 1, inclusive, at the mipmap level specified by $(I `level`).
	
	The pixels in the rectangle are processed exactly as if $(REF readPixels) had been called, but the process stops just before final conversion. At this point, all pixel component values are clamped to the range $[0,1]$ and then converted to the texture's internal format for storage in the texel array.
	
	The destination rectangle in the texture array may not include any texels outside the texture array as it was originally specified. It is not an error to specify a subtexture with zero width or height, but such a specification has no effect.
	
	When $(I `target`) is `TEXTURE_1D_ARRAY` then the y coordinate and height are treated as the start slice and number of slices to modify.
	
	If any of the pixels within the specified rectangle of the current `READ_BUFFER` are outside the read window associated with the current rendering context, then the values obtained for those pixels are undefined.
	
	No change is made to the $(I internalformat), $(I width), or $(I height), parameters of the specified texture array or to texel values outside the specified subregion.
	
	Params:
	target = Specifies the target to which the texture object is bound for $(REF copyTexSubImage2D) function. Must be `TEXTURE_1D_ARRAY`, `TEXTURE_2D`, `TEXTURE_CUBE_MAP_POSITIVE_X`, `TEXTURE_CUBE_MAP_NEGATIVE_X`, `TEXTURE_CUBE_MAP_POSITIVE_Y`, `TEXTURE_CUBE_MAP_NEGATIVE_Y`, `TEXTURE_CUBE_MAP_POSITIVE_Z`, `TEXTURE_CUBE_MAP_NEGATIVE_Z`, or `TEXTURE_RECTANGLE`.
	level = Specifies the level-of-detail number. Level 0 is the base image level. Level $(I n) is the $(I n)th mipmap reduction image.
	xoffset = Specifies a texel offset in the x direction within the texture array.
	yoffset = Specifies a texel offset in the y direction within the texture array.
	x = Specify the window coordinates of the lower left corner of the rectangular region of pixels to be copied.
	y = Specify the window coordinates of the lower left corner of the rectangular region of pixels to be copied.
	width = Specifies the width of the texture subimage.
	height = Specifies the height of the texture subimage.
	*/
	void copyTexSubImage2D(Enum target, Int level, Int xoffset, Int yoffset, Int x, Int y, Sizei width, Sizei height);
	
	/**
	Texturing maps a portion of a specified texture image onto each graphical primitive for which texturing is enabled. To enable or disable one-dimensional texturing, call $(REF enable) and $(REF disable) with argument `TEXTURE_1D`.
	
	$(REF texSubImage1D) and $(REF textureSubImage1D) redefine a contiguous subregion of an existing one-dimensional texture image. The texels referenced by $(I `pixels`) replace the portion of the existing texture array with x indices $(I `xoffset`) and xoffset + width - 1, inclusive. This region may not include any texels outside the range of the texture array as it was originally specified. It is not an error to specify a subtexture with width of 0, but such a specification has no effect.
	
	If a non-zero named buffer object is bound to the `PIXEL_UNPACK_BUFFER` target (see $(REF bindBuffer)) while a texture image is specified, $(I `pixels`) is treated as a byte offset into the buffer object's data store.
	
	Params:
	target = Specifies the target to which the texture is bound for $(REF texSubImage1D). Must be `TEXTURE_1D`.
	level = Specifies the level-of-detail number. Level 0 is the base image level. Level $(I n) is the $(I n)th mipmap reduction image.
	xoffset = Specifies a texel offset in the x direction within the texture array.
	width = Specifies the width of the texture subimage.
	format = Specifies the format of the pixel data. The following symbolic values are accepted: `RED`, `RG`, `RGB`, `BGR`, `RGBA`, `DEPTH_COMPONENT`, and `STENCIL_INDEX`.
	type = Specifies the data type of the pixel data. The following symbolic values are accepted: `UNSIGNED_BYTE`, `BYTE`, `UNSIGNED_SHORT`, `SHORT`, `UNSIGNED_INT`, `INT`, `FLOAT`, `UNSIGNED_BYTE_3_3_2`, `UNSIGNED_BYTE_2_3_3_REV`, `UNSIGNED_SHORT_5_6_5`, `UNSIGNED_SHORT_5_6_5_REV`, `UNSIGNED_SHORT_4_4_4_4`, `UNSIGNED_SHORT_4_4_4_4_REV`, `UNSIGNED_SHORT_5_5_5_1`, `UNSIGNED_SHORT_1_5_5_5_REV`, `UNSIGNED_INT_8_8_8_8`, `UNSIGNED_INT_8_8_8_8_REV`, `UNSIGNED_INT_10_10_10_2`, and `UNSIGNED_INT_2_10_10_10_REV`.
	pixels = Specifies a pointer to the image data in memory.
	*/
	void texSubImage1D(Enum target, Int level, Int xoffset, Sizei width, Enum format, Enum type, const(void)* pixels);
	
	/**
	Texturing maps a portion of a specified texture image onto each graphical primitive for which texturing is enabled.
	
	$(REF texSubImage2D) and $(REF textureSubImage2D) redefine a contiguous subregion of an existing two-dimensional or one-dimensional array texture image. The texels referenced by $(I `pixels`) replace the portion of the existing texture array with x indices $(I `xoffset`) and xoffset + width - 1, inclusive, and y indices $(I `yoffset`) and yoffset + height - 1, inclusive. This region may not include any texels outside the range of the texture array as it was originally specified. It is not an error to specify a subtexture with zero width or height, but such a specification has no effect.
	
	If a non-zero named buffer object is bound to the `PIXEL_UNPACK_BUFFER` target (see $(REF bindBuffer)) while a texture image is specified, $(I `pixels`) is treated as a byte offset into the buffer object's data store.
	
	Params:
	target = Specifies the target to which the texture is bound for $(REF texSubImage2D). Must be `TEXTURE_2D`, `TEXTURE_CUBE_MAP_POSITIVE_X`, `TEXTURE_CUBE_MAP_NEGATIVE_X`, `TEXTURE_CUBE_MAP_POSITIVE_Y`, `TEXTURE_CUBE_MAP_NEGATIVE_Y`, `TEXTURE_CUBE_MAP_POSITIVE_Z`, `TEXTURE_CUBE_MAP_NEGATIVE_Z`, or `TEXTURE_1D_ARRAY`.
	level = Specifies the level-of-detail number. Level 0 is the base image level. Level $(I n) is the $(I n)th mipmap reduction image.
	xoffset = Specifies a texel offset in the x direction within the texture array.
	yoffset = Specifies a texel offset in the y direction within the texture array.
	width = Specifies the width of the texture subimage.
	height = Specifies the height of the texture subimage.
	format = Specifies the format of the pixel data. The following symbolic values are accepted: `RED`, `RG`, `RGB`, `BGR`, `RGBA`, `BGRA`, `DEPTH_COMPONENT`, and `STENCIL_INDEX`.
	type = Specifies the data type of the pixel data. The following symbolic values are accepted: `UNSIGNED_BYTE`, `BYTE`, `UNSIGNED_SHORT`, `SHORT`, `UNSIGNED_INT`, `INT`, `FLOAT`, `UNSIGNED_BYTE_3_3_2`, `UNSIGNED_BYTE_2_3_3_REV`, `UNSIGNED_SHORT_5_6_5`, `UNSIGNED_SHORT_5_6_5_REV`, `UNSIGNED_SHORT_4_4_4_4`, `UNSIGNED_SHORT_4_4_4_4_REV`, `UNSIGNED_SHORT_5_5_5_1`, `UNSIGNED_SHORT_1_5_5_5_REV`, `UNSIGNED_INT_8_8_8_8`, `UNSIGNED_INT_8_8_8_8_REV`, `UNSIGNED_INT_10_10_10_2`, and `UNSIGNED_INT_2_10_10_10_REV`.
	pixels = Specifies a pointer to the image data in memory.
	*/
	void texSubImage2D(Enum target, Int level, Int xoffset, Int yoffset, Sizei width, Sizei height, Enum format, Enum type, const(void)* pixels);
	
	/**
	$(REF bindTexture) lets you create or use a named texture. Calling $(REF bindTexture) with $(I `target`) set to `TEXTURE_1D`, `TEXTURE_2D`, `TEXTURE_3D`, `TEXTURE_1D_ARRAY`, `TEXTURE_2D_ARRAY`, `TEXTURE_RECTANGLE`, `TEXTURE_CUBE_MAP`, `TEXTURE_CUBE_MAP_ARRAY`, `TEXTURE_BUFFER`, `TEXTURE_2D_MULTISAMPLE` or `TEXTURE_2D_MULTISAMPLE_ARRAY` and $(I `texture`) set to the name of the new texture binds the texture name to the target. When a texture is bound to a target, the previous binding for that target is automatically broken.
	
	Texture names are unsigned integers. The value zero is reserved to represent the default texture for each texture target. Texture names and the corresponding texture contents are local to the shared object space of the current GL rendering context; two rendering contexts share texture names only if they explicitly enable sharing between contexts through the appropriate GL windows interfaces functions.
	
	You must use $(REF genTextures) to generate a set of new texture names.
	
	When a texture is first bound, it assumes the specified target: A texture first bound to `TEXTURE_1D` becomes one-dimensional texture, a texture first bound to `TEXTURE_2D` becomes two-dimensional texture, a texture first bound to `TEXTURE_3D` becomes three-dimensional texture, a texture first bound to `TEXTURE_1D_ARRAY` becomes one-dimensional array texture, a texture first bound to `TEXTURE_2D_ARRAY` becomes two-dimensional array texture, a texture first bound to `TEXTURE_RECTANGLE` becomes rectangle texture, a texture first bound to `TEXTURE_CUBE_MAP` becomes a cube-mapped texture, a texture first bound to `TEXTURE_CUBE_MAP_ARRAY` becomes a cube-mapped array texture, a texture first bound to `TEXTURE_BUFFER` becomes a buffer texture, a texture first bound to `TEXTURE_2D_MULTISAMPLE` becomes a two-dimensional multisampled texture, and a texture first bound to `TEXTURE_2D_MULTISAMPLE_ARRAY` becomes a two-dimensional multisampled array texture. The state of a one-dimensional texture immediately after it is first bound is equivalent to the state of the default `TEXTURE_1D` at GL initialization, and similarly for the other texture types.
	
	While a texture is bound, GL operations on the target to which it is bound affect the bound texture, and queries of the target to which it is bound return state from the bound texture. In effect, the texture targets become aliases for the textures currently bound to them, and the texture name zero refers to the default textures that were bound to them at initialization.
	
	A texture binding created with $(REF bindTexture) remains active until a different texture is bound to the same target, or until the bound texture is deleted with $(REF deleteTextures).
	
	Once created, a named texture may be re-bound to its same original target as often as needed. It is usually much faster to use $(REF bindTexture) to bind an existing named texture to one of the texture targets than it is to reload the texture image using $(REF texImage1D), $(REF texImage2D), $(REF texImage3D) or another similar function.
	
	Params:
	target = Specifies the target to which the texture is bound. Must be one of `TEXTURE_1D`, `TEXTURE_2D`, `TEXTURE_3D`, `TEXTURE_1D_ARRAY`, `TEXTURE_2D_ARRAY`, `TEXTURE_RECTANGLE`, `TEXTURE_CUBE_MAP`, `TEXTURE_CUBE_MAP_ARRAY`, `TEXTURE_BUFFER`, `TEXTURE_2D_MULTISAMPLE` or `TEXTURE_2D_MULTISAMPLE_ARRAY`.
	texture = Specifies the name of a texture.
	*/
	void bindTexture(Enum target, UInt texture);
	
	/**
	$(REF deleteTextures) deletes $(I `n`) textures named by the elements of the array $(I `textures`). After a texture is deleted, it has no contents or dimensionality, and its name is free for reuse (for example by $(REF genTextures)). If a texture that is currently bound is deleted, the binding reverts to 0 (the default texture).
	
	$(REF deleteTextures) silently ignores 0's and names that do not correspond to existing textures.
	
	Params:
	n = Specifies the number of textures to be deleted.
	textures = Specifies an array of textures to be deleted.
	*/
	void deleteTextures(Sizei n, const(UInt)* textures);
	
	/**
	$(REF genTextures) returns $(I `n`) texture names in $(I `textures`). There is no guarantee that the names form a contiguous set of integers; however, it is guaranteed that none of the returned names was in use immediately before the call to $(REF genTextures).
	
	The generated textures have no dimensionality; they assume the dimensionality of the texture target to which they are first bound (see $(REF bindTexture)).
	
	Texture names returned by a call to $(REF genTextures) are not returned by subsequent calls, unless they are first deleted with $(REF deleteTextures).
	
	Params:
	n = Specifies the number of texture names to be generated.
	textures = Specifies an array in which the generated texture names are stored.
	*/
	void genTextures(Sizei n, UInt* textures);
	
	/**
	$(REF isTexture) returns `TRUE` if $(I `texture`) is currently the name of a texture. If $(I `texture`) is zero, or is a non-zero value that is not currently the name of a texture, or if an error occurs, $(REF isTexture) returns `FALSE`.
	
	A name returned by $(REF genTextures), but not yet associated with a texture by calling $(REF bindTexture), is not the name of a texture.
	
	Params:
	texture = Specifies a value that may be the name of a texture.
	*/
	Boolean isTexture(UInt texture);
	
	/**
	$(REF drawRangeElements) is a restricted form of $(REF drawElements). $(I `mode`), and $(I `count`) match the corresponding arguments to $(REF drawElements), with the additional constraint that all values in the arrays $(I `count`) must lie between $(I `start`) and $(I `end`), inclusive.
	
	Implementations denote recommended maximum amounts of vertex and index data, which may be queried by calling $(REF get) with argument `MAX_ELEMENTS_VERTICES` and `MAX_ELEMENTS_INDICES`. If end - start + 1 is greater than the value of `MAX_ELEMENTS_VERTICES`, or if $(I `count`) is greater than the value of `MAX_ELEMENTS_INDICES`, then the call may operate at reduced performance. There is no requirement that all vertices in the range [start, end] be referenced. However, the implementation may partially process unused vertices, reducing performance from what could be achieved with an optimal index set.
	
	When $(REF drawRangeElements) is called, it uses $(I `count`) sequential elements from an enabled array, starting at $(I `start`) to construct a sequence of geometric primitives. $(I `mode`) specifies what kind of primitives are constructed, and how the array elements construct these primitives. If more than one array is enabled, each is used.
	
	Vertex attributes that are modified by $(REF drawRangeElements) have an unspecified value after $(REF drawRangeElements) returns. Attributes that aren't modified maintain their previous values.
	
	Params:
	mode = Specifies what kind of primitives to render. Symbolic constants `POINTS`, `LINE_STRIP`, `LINE_LOOP`, `LINES`, `LINE_STRIP_ADJACENCY`, `LINES_ADJACENCY`, `TRIANGLE_STRIP`, `TRIANGLE_FAN`, `TRIANGLES`, `TRIANGLE_STRIP_ADJACENCY`, `TRIANGLES_ADJACENCY` and `PATCHES` are accepted.
	start = Specifies the minimum array index contained in $(I `indices`).
	end = Specifies the maximum array index contained in $(I `indices`).
	count = Specifies the number of elements to be rendered.
	type = Specifies the type of the values in $(I `indices`). Must be one of `UNSIGNED_BYTE`, `UNSIGNED_SHORT`, or `UNSIGNED_INT`.
	indices = Specifies a pointer to the location where the indices are stored.
	*/
	void drawRangeElements(Enum mode, UInt start, UInt end, Sizei count, Enum type, const(void)* indices);
	
	/**
	Texturing maps a portion of a specified texture image onto each graphical primitive for which texturing is enabled. To enable and disable three-dimensional texturing, call $(REF enable) and $(REF disable) with argument `TEXTURE_3D`.
	
	To define texture images, call $(REF texImage3D). The arguments describe the parameters of the texture image, such as height, width, depth, width of the border, level-of-detail number (see $(REF texParameter)), and number of color components provided. The last three arguments describe how the image is represented in memory.
	
	If $(I `target`) is `PROXY_TEXTURE_3D`, no data is read from $(I `data`), but all of the texture image state is recalculated, checked for consistency, and checked against the implementation's capabilities. If the implementation cannot handle a texture of the requested texture size, it sets all of the image state to 0, but does not generate an error (see $(REF getError)). To query for an entire mipmap array, use an image array level greater than or equal to 1.
	
	If $(I `target`) is `TEXTURE_3D`, data is read from $(I `data`) as a sequence of signed or unsigned bytes, shorts, or longs, or single-precision floating-point values, depending on $(I `type`). These values are grouped into sets of one, two, three, or four values, depending on $(I `format`), to form elements. Each data byte is treated as eight 1-bit elements, with bit ordering determined by `UNPACK_LSB_FIRST` (see $(REF pixelStore)).
	
	If a non-zero named buffer object is bound to the `PIXEL_UNPACK_BUFFER` target (see $(REF bindBuffer)) while a texture image is specified, $(I `data`) is treated as a byte offset into the buffer object's data store.
	
	The first element corresponds to the lower left corner of the texture image. Subsequent elements progress left-to-right through the remaining texels in the lowest row of the texture image, and then in successively higher rows of the texture image. The final element corresponds to the upper right corner of the texture image.
	
	$(I `format`) determines the composition of each element in $(I `data`). It can assume one of these symbolic values:
	
	- `RED`: Each element is a single red component. The GL converts it to floating point and assembles it into an RGBA element by attaching 0 for green and blue, and 1 for alpha. Each component is clamped to the range [0,1].
	
	- `RG`: Each element is a red and green pair. The GL converts each to floating point and assembles it into an RGBA element by attaching 0 for blue, and 1 for alpha. Each component is clamped to the range [0,1].
	
	- `RGB`,   `BGR`: Each element is an RGB triple. The GL converts it to floating point and assembles it into an RGBA element by attaching 1 for alpha. Each component is clamped to the range [0,1].
	
	- `RGBA`,   `BGRA`: Each element contains all four components. Each component is clamped to the range [0,1].
	
	If an application wants to store the texture at a certain resolution or in a certain format, it can request the resolution and format with $(I `internalformat`). The GL will choose an internal representation that closely approximates that requested by $(I `internalformat`), but it may not match exactly. (The representations specified by `RED`, `RG`, `RGB`, and `RGBA` must match exactly.)
	
	$(I `internalformat`) may be one of the base internal formats shown in Table 1, below
	
	$(I `internalformat`) may also be one of the sized internal formats shown in Table 2, below
	
	Finally, $(I `internalformat`) may also be one of the generic or compressed texture formats shown in Table 3 below
	
	If the $(I `internalformat`) parameter is one of the generic compressed formats, `COMPRESSED_RED`, `COMPRESSED_RG`, `COMPRESSED_RGB`, or `COMPRESSED_RGBA`, the GL will replace the internal format with the symbolic constant for a specific internal format and compress the texture before storage. If no corresponding internal format is available, or the GL can not compress that image for any reason, the internal format is instead replaced with a corresponding base internal format.
	
	If the $(I `internalformat`) parameter is `SRGB`, `SRGB8`, `SRGB_ALPHA`, or `SRGB8_ALPHA8`, the texture is treated as if the red, green, blue, or luminance components are encoded in the sRGB color space. Any alpha component is left unchanged. The conversion from the sRGB encoded component cs to a linear component cl is:
	
	cl={cs12.92ifcs≤0.04045(cs + 0.0551.055)2.4ifcs > 0.04045
	
	Assume cs is the sRGB component in the range [0,1].
	
	Use the `PROXY_TEXTURE_3D` target to try out a resolution and format. The implementation will update and recompute its best match for the requested storage resolution and format. To then query this state, call $(REF getTexLevelParameter). If the texture cannot be accommodated, texture state is set to 0.
	
	A one-component texture image uses only the red component of the RGBA color extracted from $(I `data`). A two-component image uses the R and A values. A three-component image uses the R, G, and B values. A four-component image uses all of the RGBA components.
	
	Params:
	target = Specifies the target texture. Must be one of `TEXTURE_3D`, `PROXY_TEXTURE_3D`, `TEXTURE_2D_ARRAY` or `PROXY_TEXTURE_2D_ARRAY`.
	level = Specifies the level-of-detail number. Level 0 is the base image level. Level n is the  n th   mipmap reduction image.
	internalformat = Specifies the number of color components in the texture. Must be one of base internal formats given in Table 1, one of the sized internal formats given in Table 2, or one of the compressed internal formats given in Table 3, below.
	width = Specifies the width of the texture image. All implementations support 3D texture images that are at least 16 texels wide.
	height = Specifies the height of the texture image. All implementations support 3D texture images that are at least 256 texels high.
	depth = Specifies the depth of the texture image, or the number of layers in a texture array. All implementations support 3D texture images that are at least 256 texels deep, and texture arrays that are at least 256 layers deep.
	border = This value must be 0.
	format = Specifies the format of the pixel data. The following symbolic values are accepted: `RED`, `RG`, `RGB`, `BGR`, `RGBA`, `BGRA`, `RED_INTEGER`, `RG_INTEGER`, `RGB_INTEGER`, `BGR_INTEGER`, `RGBA_INTEGER`, `BGRA_INTEGER`, `STENCIL_INDEX`, `DEPTH_COMPONENT`, `DEPTH_STENCIL`.
	type = Specifies the data type of the pixel data. The following symbolic values are accepted: `UNSIGNED_BYTE`, `BYTE`, `UNSIGNED_SHORT`, `SHORT`, `UNSIGNED_INT`, `INT`, `HALF_FLOAT`, `FLOAT`, `UNSIGNED_BYTE_3_3_2`, `UNSIGNED_BYTE_2_3_3_REV`, `UNSIGNED_SHORT_5_6_5`, `UNSIGNED_SHORT_5_6_5_REV`, `UNSIGNED_SHORT_4_4_4_4`, `UNSIGNED_SHORT_4_4_4_4_REV`, `UNSIGNED_SHORT_5_5_5_1`, `UNSIGNED_SHORT_1_5_5_5_REV`, `UNSIGNED_INT_8_8_8_8`, `UNSIGNED_INT_8_8_8_8_REV`, `UNSIGNED_INT_10_10_10_2`, and `UNSIGNED_INT_2_10_10_10_REV`.
	data = Specifies a pointer to the image data in memory.
	*/
	void texImage3D(Enum target, Int level, Int internalformat, Sizei width, Sizei height, Sizei depth, Int border, Enum format, Enum type, const(void)* data);
	
	/**
	Texturing maps a portion of a specified texture image onto each graphical primitive for which texturing is enabled.
	
	$(REF texSubImage3D) and $(REF textureSubImage3D) redefine a contiguous subregion of an existing three-dimensional or two-dimensioanl array texture image. The texels referenced by $(I `pixels`) replace the portion of the existing texture array with x indices $(I `xoffset`) and xoffset + width - 1, inclusive, y indices $(I `yoffset`) and yoffset + height - 1, inclusive, and z indices $(I `zoffset`) and zoffset + depth - 1, inclusive. For three-dimensional textures, the z index refers to the third dimension. For two-dimensional array textures, the z index refers to the slice index. This region may not include any texels outside the range of the texture array as it was originally specified. It is not an error to specify a subtexture with zero width, height, or depth but such a specification has no effect.
	
	If a non-zero named buffer object is bound to the `PIXEL_UNPACK_BUFFER` target (see $(REF bindBuffer)) while a texture image is specified, $(I `pixels`) is treated as a byte offset into the buffer object's data store.
	
	Params:
	target = Specifies the target to which the texture is bound for $(REF texSubImage3D). Must be `TEXTURE_3D` or `TEXTURE_2D_ARRAY`.
	level = Specifies the level-of-detail number. Level 0 is the base image level. Level $(I n) is the $(I n)th mipmap reduction image.
	xoffset = Specifies a texel offset in the x direction within the texture array.
	yoffset = Specifies a texel offset in the y direction within the texture array.
	zoffset = Specifies a texel offset in the z direction within the texture array.
	width = Specifies the width of the texture subimage.
	height = Specifies the height of the texture subimage.
	depth = Specifies the depth of the texture subimage.
	format = Specifies the format of the pixel data. The following symbolic values are accepted: `RED`, `RG`, `RGB`, `BGR`, `RGBA`, `DEPTH_COMPONENT`, and `STENCIL_INDEX`.
	type = Specifies the data type of the pixel data. The following symbolic values are accepted: `UNSIGNED_BYTE`, `BYTE`, `UNSIGNED_SHORT`, `SHORT`, `UNSIGNED_INT`, `INT`, `FLOAT`, `UNSIGNED_BYTE_3_3_2`, `UNSIGNED_BYTE_2_3_3_REV`, `UNSIGNED_SHORT_5_6_5`, `UNSIGNED_SHORT_5_6_5_REV`, `UNSIGNED_SHORT_4_4_4_4`, `UNSIGNED_SHORT_4_4_4_4_REV`, `UNSIGNED_SHORT_5_5_5_1`, `UNSIGNED_SHORT_1_5_5_5_REV`, `UNSIGNED_INT_8_8_8_8`, `UNSIGNED_INT_8_8_8_8_REV`, `UNSIGNED_INT_10_10_10_2`, and `UNSIGNED_INT_2_10_10_10_REV`.
	pixels = Specifies a pointer to the image data in memory.
	*/
	void texSubImage3D(Enum target, Int level, Int xoffset, Int yoffset, Int zoffset, Sizei width, Sizei height, Sizei depth, Enum format, Enum type, const(void)* pixels);
	
	/**
	$(REF copyTexSubImage3D) and $(REF copyTextureSubImage3D) functions replace a rectangular portion of a three-dimensional or two-dimensional array texture image with pixels from the current `READ_BUFFER` (rather than from main memory, as is the case for $(REF texSubImage3D)).
	
	The screen-aligned pixel rectangle with lower left corner at ($(I `x`), $(I `y`)) and with width $(I `width`) and height $(I `height`) replaces the portion of the texture array with x indices $(I `xoffset`) through xoffset + width - 1, inclusive, and y indices $(I `yoffset`) through yoffset + height - 1, inclusive, at z index $(I `zoffset`) and at the mipmap level specified by $(I `level`).
	
	The pixels in the rectangle are processed exactly as if $(REF readPixels) had been called, but the process stops just before final conversion. At this point, all pixel component values are clamped to the range [0, 1] and then converted to the texture's internal format for storage in the texel array.
	
	The destination rectangle in the texture array may not include any texels outside the texture array as it was originally specified. It is not an error to specify a subtexture with zero width or height, but such a specification has no effect.
	
	If any of the pixels within the specified rectangle of the current `READ_BUFFER` are outside the read window associated with the current rendering context, then the values obtained for those pixels are undefined.
	
	No change is made to the $(I internalformat), $(I width), $(I height), $(I depth), or $(I border) parameters of the specified texture array or to texel values outside the specified subregion.
	
	Params:
	target = Specifies the target to which the texture object is bound for $(REF copyTexSubImage3D) function. Must be `TEXTURE_3D`, `TEXTURE_2D_ARRAY` or `TEXTURE_CUBE_MAP_ARRAY`.
	level = Specifies the level-of-detail number. Level 0 is the base image level. Level $(I n) is the $(I n)th mipmap reduction image.
	xoffset = Specifies a texel offset in the x direction within the texture array.
	yoffset = Specifies a texel offset in the y direction within the texture array.
	zoffset = Specifies a texel offset in the z direction within the texture array.
	x = Specify the window coordinates of the lower left corner of the rectangular region of pixels to be copied.
	y = Specify the window coordinates of the lower left corner of the rectangular region of pixels to be copied.
	width = Specifies the width of the texture subimage.
	height = Specifies the height of the texture subimage.
	*/
	void copyTexSubImage3D(Enum target, Int level, Int xoffset, Int yoffset, Int zoffset, Int x, Int y, Sizei width, Sizei height);
	
	/**
	$(REF activeTexture) selects which texture unit subsequent texture state calls will affect. The number of texture units an implementation supports is implementation dependent, but must be at least 80.
	
	Params:
	texture = Specifies which texture unit to make active. The number of texture units is implementation dependent, but must be at least 80. $(I `texture`) must be one of `TEXTURE`$(I i), where $(I i) ranges from zero to the value of `MAX_COMBINED_TEXTURE_IMAGE_UNITS` minus one. The initial value is `TEXTURE0`.
	*/
	void activeTexture(Enum texture);
	
	/**
	Multisampling samples a pixel multiple times at various implementation-dependent subpixel locations to generate antialiasing effects. Multisampling transparently antialiases points, lines, polygons, and images if it is enabled.
	
	$(I `value`) is used in constructing a temporary mask used in determining which samples will be used in resolving the final fragment color. This mask is bitwise-anded with the coverage mask generated from the multisampling computation. If the $(I `invert`) flag is set, the temporary mask is inverted (all bits flipped) and then the bitwise-and is computed.
	
	If an implementation does not have any multisample buffers available, or multisampling is disabled, rasterization occurs with only a single sample computing a pixel's final RGB color.
	
	Provided an implementation supports multisample buffers, and multisampling is enabled, then a pixel's final color is generated by combining several samples per pixel. Each sample contains color, depth, and stencil information, allowing those operations to be performed on each sample.
	
	Params:
	value = Specify a single floating-point sample coverage value. The value is clamped to the range   0 1  . The initial value is 1.0.
	invert = Specify a single boolean value representing if the coverage masks should be inverted. `TRUE` and `FALSE` are accepted. The initial value is `FALSE`.
	*/
	void sampleCoverage(Float value, Boolean invert);
	
	/**
	Texturing allows elements of an image array to be read by shaders.
	
	$(REF compressedTexImage3D) loads a previously defined, and retrieved, compressed three-dimensional texture image if $(I `target`) is `TEXTURE_3D` (see $(REF texImage3D)).
	
	If $(I `target`) is `TEXTURE_2D_ARRAY`, $(I `data`) is treated as an array of compressed 2D textures.
	
	If $(I `target`) is `PROXY_TEXTURE_3D` or `PROXY_TEXTURE_2D_ARRAY`, no data is read from $(I `data`), but all of the texture image state is recalculated, checked for consistency, and checked against the implementation's capabilities. If the implementation cannot handle a texture of the requested texture size, it sets all of the image state to 0, but does not generate an error (see $(REF getError)). To query for an entire mipmap array, use an image array level greater than or equal to 1.
	
	$(I `internalformat`) must be a known compressed image format (such as `RGTC`) or an extension-specified compressed-texture format. When a texture is loaded with $(REF texImage2D) using a generic compressed texture format (e.g., `COMPRESSED_RGB`), the GL selects from one of its extensions supporting compressed textures. In order to load the compressed texture image using $(REF compressedTexImage3D), query the compressed texture image's size and format using $(REF getTexLevelParameter).
	
	If a non-zero named buffer object is bound to the `PIXEL_UNPACK_BUFFER` target (see $(REF bindBuffer)) while a texture image is specified, $(I `data`) is treated as a byte offset into the buffer object's data store.
	
	If the compressed data are arranged into fixed-size blocks of texels, the pixel storage modes can be used to select a sub-rectangle from a larger containing rectangle. These pixel storage modes operate in the same way as they do for $(REF texImage1D). In the following description, denote by bs, bw, bh, and bd the values of pixel storage modes `UNPACK_COMPRESSED_BLOCK_SIZE`, `UNPACK_COMPRESSED_BLOCK_WIDTH`, `UNPACK_COMPRESSED_BLOCK_HEIGHT`, and `UNPACK_COMPRESSED_BLOCK_DEPTH`, respectively. bs is the compressed block size in bytes; bw, bh, and bd are the compressed block width, height, and depth in pixels.
	
	By default the pixel storage modes `UNPACK_ROW_LENGTH`, `UNPACK_SKIP_ROWS`, `UNPACK_SKIP_PIXELS`, `UNPACK_IMAGE_HEIGHT` and `UNPACK_SKIP_IMAGES` are ignored for compressed images. To enable `UNPACK_SKIP_PIXELS` and `UNPACK_ROW_LENGTH`, bs and bw must both be non-zero. To also enable `UNPACK_SKIP_ROWS` and `UNPACK_IMAGE_HEIGHT`, bh must be non-zero. To also enable `UNPACK_SKIP_IMAGES`, bd must be non-zero. All parameters must be consistent with the compressed format to produce the desired results.
	
	When selecting a sub-rectangle from a compressed image:
	
	$(I `imageSize`) must be equal to:
	
	bs×⌈widthbw⌉×⌈heightbh⌉×⌈depthbd⌉
	
	Params:
	target = Specifies the target texture. Must be `TEXTURE_3D`, `PROXY_TEXTURE_3D`, `TEXTURE_2D_ARRAY` or `PROXY_TEXTURE_2D_ARRAY`.
	level = Specifies the level-of-detail number. Level 0 is the base image level. Level $(I n) is the $(I n)th mipmap reduction image.
	internalformat = Specifies the format of the compressed image data stored at address $(I `data`).
	width = Specifies the width of the texture image. All implementations support 3D texture images that are at least 16 texels wide.
	height = Specifies the height of the texture image. All implementations support 3D texture images that are at least 16 texels high.
	depth = Specifies the depth of the texture image. All implementations support 3D texture images that are at least 16 texels deep.
	border = This value must be 0.
	imageSize = Specifies the number of unsigned bytes of image data starting at the address specified by $(I `data`).
	data = Specifies a pointer to the compressed image data in memory.
	*/
	void compressedTexImage3D(Enum target, Int level, Enum internalformat, Sizei width, Sizei height, Sizei depth, Int border, Sizei imageSize, const(void)* data);
	
	/**
	Texturing allows elements of an image array to be read by shaders.
	
	$(REF compressedTexImage2D) loads a previously defined, and retrieved, compressed two-dimensional texture image if $(I `target`) is `TEXTURE_2D`, or one of the cube map faces such as `TEXTURE_CUBE_MAP_POSITIVE_X`. (see $(REF texImage2D)).
	
	If $(I `target`) is `TEXTURE_1D_ARRAY`, $(I `data`) is treated as an array of compressed 1D textures.
	
	If $(I `target`) is `PROXY_TEXTURE_2D`, `PROXY_TEXTURE_1D_ARRAY` or `PROXY_TEXTURE_CUBE_MAP`, no data is read from $(I `data`), but all of the texture image state is recalculated, checked for consistency, and checked against the implementation's capabilities. If the implementation cannot handle a texture of the requested texture size, it sets all of the image state to 0, but does not generate an error (see $(REF getError)). To query for an entire mipmap array, use an image array level greater than or equal to 1.
	
	$(I `internalformat`) must be a known compressed image format (such as `RGTC`) or an extension-specified compressed-texture format. When a texture is loaded with $(REF texImage2D) using a generic compressed texture format (e.g., `COMPRESSED_RGB`), the GL selects from one of its extensions supporting compressed textures. In order to load the compressed texture image using $(REF compressedTexImage2D), query the compressed texture image's size and format using $(REF getTexLevelParameter).
	
	If a non-zero named buffer object is bound to the `PIXEL_UNPACK_BUFFER` target (see $(REF bindBuffer)) while a texture image is specified, $(I `data`) is treated as a byte offset into the buffer object's data store.
	
	If the compressed data are arranged into fixed-size blocks of texels, the pixel storage modes can be used to select a sub-rectangle from a larger containing rectangle. These pixel storage modes operate in the same way as they do for $(REF texImage2D). In the following description, denote by bs, bw, bh, and bd, the values of pixel storage modes `UNPACK_COMPRESSED_BLOCK_SIZE`, `UNPACK_COMPRESSED_BLOCK_WIDTH`, `UNPACK_COMPRESSED_BLOCK_HEIGHT`, and `UNPACK_COMPRESSED_BLOCK_DEPTH`, respectively. bs is the compressed block size in bytes; bw, bh, and bd are the compressed block width, height, and depth in pixels.
	
	By default the pixel storage modes `UNPACK_ROW_LENGTH`, `UNPACK_SKIP_ROWS`, `UNPACK_SKIP_PIXELS`, `UNPACK_IMAGE_HEIGHT` and `UNPACK_SKIP_IMAGES` are ignored for compressed images. To enable `UNPACK_SKIP_PIXELS` and `UNPACK_ROW_LENGTH`, bs and bw must both be non-zero. To also enable `UNPACK_SKIP_ROWS` and `UNPACK_IMAGE_HEIGHT`, bh must be non-zero. To also enable `UNPACK_SKIP_IMAGES`, bd must be non-zero. All parameters must be consistent with the compressed format to produce the desired results.
	
	When selecting a sub-rectangle from a compressed image:
	
	$(I `imageSize`) must be equal to:
	
	bs×⌈widthbw⌉×⌈heightbh⌉
	
	Params:
	target = Specifies the target texture. Must be `TEXTURE_2D`, `PROXY_TEXTURE_2D`, `TEXTURE_1D_ARRAY`, `PROXY_TEXTURE_1D_ARRAY`, `TEXTURE_CUBE_MAP_POSITIVE_X`, `TEXTURE_CUBE_MAP_NEGATIVE_X`, `TEXTURE_CUBE_MAP_POSITIVE_Y`, `TEXTURE_CUBE_MAP_NEGATIVE_Y`, `TEXTURE_CUBE_MAP_POSITIVE_Z`, `TEXTURE_CUBE_MAP_NEGATIVE_Z`, or `PROXY_TEXTURE_CUBE_MAP`.
	level = Specifies the level-of-detail number. Level 0 is the base image level. Level $(I n) is the $(I n)th mipmap reduction image.
	internalformat = Specifies the format of the compressed image data stored at address $(I `data`).
	width = Specifies the width of the texture image. All implementations support 2D texture and cube map texture images that are at least 16384 texels wide.
	height = Specifies the height of the texture image. All implementations support 2D texture and cube map texture images that are at least 16384 texels high.
	border = This value must be 0.
	imageSize = Specifies the number of unsigned bytes of image data starting at the address specified by $(I `data`).
	data = Specifies a pointer to the compressed image data in memory.
	*/
	void compressedTexImage2D(Enum target, Int level, Enum internalformat, Sizei width, Sizei height, Int border, Sizei imageSize, const(void)* data);
	
	/**
	Texturing allows elements of an image array to be read by shaders.
	
	$(REF compressedTexImage1D) loads a previously defined, and retrieved, compressed one-dimensional texture image if $(I `target`) is `TEXTURE_1D` (see $(REF texImage1D)).
	
	If $(I `target`) is `PROXY_TEXTURE_1D`, no data is read from $(I `data`), but all of the texture image state is recalculated, checked for consistency, and checked against the implementation's capabilities. If the implementation cannot handle a texture of the requested texture size, it sets all of the image state to 0, but does not generate an error (see $(REF getError)). To query for an entire mipmap array, use an image array level greater than or equal to 1.
	
	$(I `internalformat`) must be an extension-specified compressed-texture format. When a texture is loaded with $(REF texImage1D) using a generic compressed texture format (e.g., `COMPRESSED_RGB`) the GL selects from one of its extensions supporting compressed textures. In order to load the compressed texture image using $(REF compressedTexImage1D), query the compressed texture image's size and format using $(REF getTexLevelParameter).
	
	If a non-zero named buffer object is bound to the `PIXEL_UNPACK_BUFFER` target (see $(REF bindBuffer)) while a texture image is specified, $(I `data`) is treated as a byte offset into the buffer object's data store.
	
	If the compressed data are arranged into fixed-size blocks of texels, the pixel storage modes can be used to select a sub-rectangle from a larger containing rectangle. These pixel storage modes operate in the same way as they do for $(REF texImage1D). In the following description, denote by bs, bw, bh, and bd the values of pixel storage modes `UNPACK_COMPRESSED_BLOCK_SIZE`, `UNPACK_COMPRESSED_BLOCK_WIDTH`, `UNPACK_COMPRESSED_BLOCK_HEIGHT`, and `UNPACK_COMPRESSED_BLOCK_DEPTH`, respectively. bs is the compressed block size in bytes; bw, bh, and bd are the compressed block width, height, and depth in pixels.
	
	By default the pixel storage modes `UNPACK_ROW_LENGTH`, `UNPACK_SKIP_ROWS`, `UNPACK_SKIP_PIXELS`, `UNPACK_IMAGE_HEIGHT` and `UNPACK_SKIP_IMAGES` are ignored for compressed images. To enable `UNPACK_SKIP_PIXELS` and `UNPACK_ROW_LENGTH`, bs and bw must both be non-zero. To also enable `UNPACK_SKIP_ROWS` and `UNPACK_IMAGE_HEIGHT`, bh must be non-zero. To also enable `UNPACK_SKIP_IMAGES`, bd must be non-zero. All parameters must be consistent with the compressed format to produce the desired results.
	
	When selecting a sub-rectangle from a compressed image,
	
	$(I `imageSize`) must be equal to:
	
	bs×⌈widthbw⌉
	
	Params:
	target = Specifies the target texture. Must be `TEXTURE_1D` or `PROXY_TEXTURE_1D`.
	level = Specifies the level-of-detail number. Level 0 is the base image level. Level $(I n) is the $(I n)th mipmap reduction image.
	internalformat = Specifies the format of the compressed image data stored at address $(I `data`).
	width = Specifies the width of the texture image. All implementations support texture images that are at least 64 texels wide. The height of the 1D texture image is 1.
	border = This value must be 0.
	imageSize = Specifies the number of unsigned bytes of image data starting at the address specified by $(I `data`).
	data = Specifies a pointer to the compressed image data in memory.
	*/
	void compressedTexImage1D(Enum target, Int level, Enum internalformat, Sizei width, Int border, Sizei imageSize, const(void)* data);
	
	/**
	Texturing allows elements of an image array to be read by shaders.
	
	$(REF compressedTexSubImage3D) and $(REF compressedTextureSubImage3D) redefine a contiguous subregion of an existing three-dimensional texture image. The texels referenced by $(I `data`) replace the portion of the existing texture array with x indices $(I `xoffset`) and xoffset + width - 1, and the y indices $(I `yoffset`) and yoffset + height - 1, and the z indices $(I `zoffset`) and zoffset + depth - 1, inclusive. This region may not include any texels outside the range of the texture array as it was originally specified. It is not an error to specify a subtexture with width of 0, but such a specification has no effect.
	
	$(I `internalformat`) must be a known compressed image format (such as `RGTC`) or an extension-specified compressed-texture format. The $(I `format`) of the compressed texture image is selected by the GL implementation that compressed it (see $(REF texImage3D)) and should be queried at the time the texture was compressed with $(REF getTexLevelParameter).
	
	If a non-zero named buffer object is bound to the `PIXEL_UNPACK_BUFFER` target (see $(REF bindBuffer)) while a texture image is specified, $(I `data`) is treated as a byte offset into the buffer object's data store.
	
	Params:
	target = Specifies the target to which the texture is bound for $(REF compressedTexSubImage3D) function. Must be `TEXTURE_2D_ARRAY`, `TEXTURE_3D`, or `TEXTURE_CUBE_MAP_ARRAY`.
	level = Specifies the level-of-detail number. Level 0 is the base image level. Level $(I n) is the $(I n)th mipmap reduction image.
	xoffset = Specifies a texel offset in the x direction within the texture array.
	yoffset = Specifies a texel offset in the y direction within the texture array.
	zoffset = Undocumented in OpenGL reference
	width = Specifies the width of the texture subimage.
	height = Specifies the height of the texture subimage.
	depth = Specifies the depth of the texture subimage.
	format = Specifies the format of the compressed image data stored at address $(I `data`).
	imageSize = Specifies the number of unsigned bytes of image data starting at the address specified by $(I `data`).
	data = Specifies a pointer to the compressed image data in memory.
	*/
	void compressedTexSubImage3D(Enum target, Int level, Int xoffset, Int yoffset, Int zoffset, Sizei width, Sizei height, Sizei depth, Enum format, Sizei imageSize, const(void)* data);
	
	/**
	Texturing allows elements of an image array to be read by shaders.
	
	$(REF compressedTexSubImage2D) and $(REF compressedTextureSubImage2D) redefine a contiguous subregion of an existing two-dimensional texture image. The texels referenced by $(I `data`) replace the portion of the existing texture array with x indices $(I `xoffset`) and xoffset + width - 1, and the y indices $(I `yoffset`) and yoffset + height - 1, inclusive. This region may not include any texels outside the range of the texture array as it was originally specified. It is not an error to specify a subtexture with width of 0, but such a specification has no effect.
	
	$(I `internalformat`) must be a known compressed image format (such as `RGTC`) or an extension-specified compressed-texture format. The $(I `format`) of the compressed texture image is selected by the GL implementation that compressed it (see $(REF texImage2D)) and should be queried at the time the texture was compressed with $(REF getTexLevelParameter).
	
	If a non-zero named buffer object is bound to the `PIXEL_UNPACK_BUFFER` target (see $(REF bindBuffer)) while a texture image is specified, $(I `data`) is treated as a byte offset into the buffer object's data store.
	
	Params:
	target = Specifies the target to which the texture is bound for $(REF compressedTexSubImage2D) function. Must be `TEXTURE_1D_ARRAY`, `TEXTURE_2D`, `TEXTURE_CUBE_MAP_POSITIVE_X`, `TEXTURE_CUBE_MAP_NEGATIVE_X`, `TEXTURE_CUBE_MAP_POSITIVE_Y`, `TEXTURE_CUBE_MAP_NEGATIVE_Y`, `TEXTURE_CUBE_MAP_POSITIVE_Z`, or `TEXTURE_CUBE_MAP_NEGATIVE_Z`.
	level = Specifies the level-of-detail number. Level 0 is the base image level. Level $(I n) is the $(I n)th mipmap reduction image.
	xoffset = Specifies a texel offset in the x direction within the texture array.
	yoffset = Specifies a texel offset in the y direction within the texture array.
	width = Specifies the width of the texture subimage.
	height = Specifies the height of the texture subimage.
	format = Specifies the format of the compressed image data stored at address $(I `data`).
	imageSize = Specifies the number of unsigned bytes of image data starting at the address specified by $(I `data`).
	data = Specifies a pointer to the compressed image data in memory.
	*/
	void compressedTexSubImage2D(Enum target, Int level, Int xoffset, Int yoffset, Sizei width, Sizei height, Enum format, Sizei imageSize, const(void)* data);
	
	/**
	Texturing allows elements of an image array to be read by shaders.
	
	$(REF compressedTexSubImage1D) and $(REF compressedTextureSubImage1D) redefine a contiguous subregion of an existing one-dimensional texture image. The texels referenced by $(I `data`) replace the portion of the existing texture array with x indices $(I `xoffset`) and xoffset + width - 1, inclusive. This region may not include any texels outside the range of the texture array as it was originally specified. It is not an error to specify a subtexture with width of 0, but such a specification has no effect.
	
	$(I `internalformat`) must be a known compressed image format (such as `RGTC`) or an extension-specified compressed-texture format. The $(I `format`) of the compressed texture image is selected by the GL implementation that compressed it (see $(REF texImage1D)), and should be queried at the time the texture was compressed with $(REF getTexLevelParameter).
	
	If a non-zero named buffer object is bound to the `PIXEL_UNPACK_BUFFER` target (see $(REF bindBuffer)) while a texture image is specified, $(I `data`) is treated as a byte offset into the buffer object's data store.
	
	Params:
	target = Specifies the target, to which the texture is bound, for $(REF compressedTexSubImage1D) function. Must be `TEXTURE_1D`.
	level = Specifies the level-of-detail number. Level 0 is the base image level. Level $(I n) is the $(I n)th mipmap reduction image.
	xoffset = Specifies a texel offset in the x direction within the texture array.
	width = Specifies the width of the texture subimage.
	format = Specifies the format of the compressed image data stored at address $(I `data`).
	imageSize = Specifies the number of unsigned bytes of image data starting at the address specified by $(I `data`).
	data = Specifies a pointer to the compressed image data in memory.
	*/
	void compressedTexSubImage1D(Enum target, Int level, Int xoffset, Sizei width, Enum format, Sizei imageSize, const(void)* data);
	
	/**
	$(REF getCompressedTexImage) and $(REF getnCompressedTexImage) return the compressed texture image associated with $(I `target`) and $(I `lod`) into $(I `pixels`). $(REF getCompressedTextureImage) serves the same purpose, but instead of taking a texture target, it takes the ID of the texture object. $(I `pixels`) should be an array of $(I `bufSize`) bytes for $(REF getnCompresedTexImage) and $(REF getCompressedTextureImage) functions, and of `TEXTURE_COMPRESSED_IMAGE_SIZE` bytes in case of $(REF getCompressedTexImage). If the actual data takes less space than $(I `bufSize`), the remaining bytes will not be touched. $(I `target`) specifies the texture target, to which the texture the data the function should extract the data from is bound to. $(I `lod`) specifies the level-of-detail number of the desired image.
	
	If a non-zero named buffer object is bound to the `PIXEL_PACK_BUFFER` target (see $(REF bindBuffer)) while a texture image is requested, $(I `pixels`) is treated as a byte offset into the buffer object's data store.
	
	To minimize errors, first verify that the texture is compressed by calling $(REF getTexLevelParameter) with argument `TEXTURE_COMPRESSED`. If the texture is compressed, you can determine the amount of memory required to store the compressed texture by calling $(REF getTexLevelParameter) with argument `TEXTURE_COMPRESSED_IMAGE_SIZE`. Finally, retrieve the internal format of the texture by calling $(REF getTexLevelParameter) with argument `TEXTURE_INTERNAL_FORMAT`. To store the texture for later use, associate the internal format and size with the retrieved texture image. These data can be used by the respective texture or subtexture loading routine used for loading $(I `target`) textures.
	
	Params:
	target = Specifies the target to which the texture is bound for $(REF getCompressedTexImage) and $(REF getnCompressedTexImage) functions. `TEXTURE_1D`, `TEXTURE_1D_ARRAY`, `TEXTURE_2D`, `TEXTURE_2D_ARRAY`, `TEXTURE_3D`, `TEXTURE_CUBE_MAP_ARRAY`, `TEXTURE_CUBE_MAP_POSITIVE_X`, `TEXTURE_CUBE_MAP_NEGATIVE_X`, `TEXTURE_CUBE_MAP_POSITIVE_Y`, `TEXTURE_CUBE_MAP_NEGATIVE_Y`, `TEXTURE_CUBE_MAP_POSITIVE_Z`, and `TEXTURE_CUBE_MAP_NEGATIVE_Z`, `TEXTURE_RECTANGLE` are accepted.
	level = Specifies the level-of-detail number of the desired image. Level 0 is the base image level. Level $n$ is the $n$-th mipmap reduction image.
	pixels = Returns the compressed texture image.
	*/
	void getCompressedTexImage(Enum target, Int level, void* pixels);
	
	/**
	Pixels can be drawn using a function that blends the incoming (source) RGBA values with the RGBA values that are already in the frame buffer (the destination values). Blending is initially disabled. Use $(REF enable) and $(REF disable) with argument `BLEND` to enable and disable blending.
	
	$(REF blendFuncSeparate) defines the operation of blending for all draw buffers when it is enabled. $(REF blendFuncSeparatei) defines the operation of blending for a single draw buffer specified by $(I `buf`) when enabled for that draw buffer. $(I `srcRGB`) specifies which method is used to scale the source RGB-color components. $(I `dstRGB`) specifies which method is used to scale the destination RGB-color components. Likewise, $(I `srcAlpha`) specifies which method is used to scale the source alpha color component, and $(I `dstAlpha`) specifies which method is used to scale the destination alpha component. The possible methods are described in the following table. Each method defines four scale factors, one each for red, green, blue, and alpha.
	
	In the table and in subsequent equations, first source, second source and destination color components are referred to as (Rs0, Gs0, Bs0, As0), (Rs1, Gs1, Bs1, As1), and (Rd, Gd, Bd, Ad), respectively. The color specified by $(REF blendColor) is referred to as (Rc, Gc, Bc, Ac). They are understood to have integer values between 0 and (kR, kG, kB, kA), where
	
	kc=2mc - 1
	
	and (mR, mG, mB, mA) is the number of red, green, blue, and alpha bitplanes.
	
	Source and destination scale factors are referred to as (sR, sG, sB, sA) and (dR, dG, dB, dA). All scale factors have range [0, 1].
	
	In the table,
	
	i=min⁡(As, 1 - Ad)
	
	To determine the blended RGBA values of a pixel, the system uses the following equations:
	
	Rd=min⁡(kR, Rs⁢sR + Rd⁢dR) Gd=min⁡(kG, Gs⁢sG + Gd⁢dG) Bd=min⁡(kB, Bs⁢sB + Bd⁢dB) Ad=min⁡(kA, As⁢sA + Ad⁢dA)
	
	Despite the apparent precision of the above equations, blending arithmetic is not exactly specified, because blending operates with imprecise integer color values. However, a blend factor that should be equal to 1 is guaranteed not to modify its multiplicand, and a blend factor equal to 0 reduces its multiplicand to 0. For example, when $(I `srcRGB`) is `SRC_ALPHA`, $(I `dstRGB`) is `ONE_MINUS_SRC_ALPHA`, and As is equal to kA, the equations reduce to simple replacement:
	
	Rd=Rs Gd=Gs Bd=Bs Ad=As
	
	Params:
	srcRGB = Specifies how the red, green, and blue blending factors are computed. The initial value is `ONE`.
	dstRGB = Specifies how the red, green, and blue destination blending factors are computed. The initial value is `ZERO`.
	srcAlpha = Specified how the alpha source blending factor is computed. The initial value is `ONE`.
	dstAlpha = Specified how the alpha destination blending factor is computed. The initial value is `ZERO`.
	*/
	void blendFuncSeparate(Enum srcRGB, Enum dstRGB, Enum srcAlpha, Enum dstAlpha);
	
	/**
	$(REF multiDrawArrays) specifies multiple sets of geometric primitives with very few subroutine calls. Instead of calling a GL procedure to pass each individual vertex, normal, texture coordinate, edge flag, or color, you can prespecify separate arrays of vertices, normals, and colors and use them to construct a sequence of primitives with a single call to $(REF multiDrawArrays).
	
	$(REF multiDrawArrays) behaves identically to $(REF drawArrays) except that $(I `drawcount`) separate ranges of elements are specified instead.
	
	When $(REF multiDrawArrays) is called, it uses $(I `count`) sequential elements from each enabled array to construct a sequence of geometric primitives, beginning with element $(I `first`). $(I `mode`) specifies what kind of primitives are constructed, and how the array elements construct those primitives.
	
	Vertex attributes that are modified by $(REF multiDrawArrays) have an unspecified value after $(REF multiDrawArrays) returns. Attributes that aren't modified remain well defined.
	
	Params:
	mode = Specifies what kind of primitives to render. Symbolic constants `POINTS`, `LINE_STRIP`, `LINE_LOOP`, `LINES`, `LINE_STRIP_ADJACENCY`, `LINES_ADJACENCY`, `TRIANGLE_STRIP`, `TRIANGLE_FAN`, `TRIANGLES`, `TRIANGLE_STRIP_ADJACENCY`, `TRIANGLES_ADJACENCY` and `PATCHES` are accepted.
	first = Points to an array of starting indices in the enabled arrays.
	count = Points to an array of the number of indices to be rendered.
	drawcount = Specifies the size of the first and count
	*/
	void multiDrawArrays(Enum mode, const(Int)* first, const(Sizei)* count, Sizei drawcount);
	
	/**
	$(REF multiDrawElements) specifies multiple sets of geometric primitives with very few subroutine calls. Instead of calling a GL function to pass each individual vertex, normal, texture coordinate, edge flag, or color, you can prespecify separate arrays of vertices, normals, and so on, and use them to construct a sequence of primitives with a single call to $(REF multiDrawElements).
	
	$(REF multiDrawElements) is identical in operation to $(REF drawElements) except that $(I `drawcount`) separate lists of elements are specified.
	
	Vertex attributes that are modified by $(REF multiDrawElements) have an unspecified value after $(REF multiDrawElements) returns. Attributes that aren't modified maintain their previous values.
	
	Params:
	mode = Specifies what kind of primitives to render. Symbolic constants `POINTS`, `LINE_STRIP`, `LINE_LOOP`, `LINES`, `LINE_STRIP_ADJACENCY`, `LINES_ADJACENCY`, `TRIANGLE_STRIP`, `TRIANGLE_FAN`, `TRIANGLES`, `TRIANGLE_STRIP_ADJACENCY`, `TRIANGLES_ADJACENCY` and `PATCHES` are accepted.
	count = Points to an array of the elements counts.
	type = Specifies the type of the values in $(I `indices`). Must be one of `UNSIGNED_BYTE`, `UNSIGNED_SHORT`, or `UNSIGNED_INT`.
	indices = Specifies a pointer to the location where the indices are stored.
	drawcount = Specifies the size of the $(I `count`) and $(I `indices`) arrays.
	*/
	void multiDrawElements(Enum mode, const(Sizei)* count, Enum type, const(void)* indices, Sizei drawcount);
	
	/**
	The following values are accepted for $(I `pname`):
	
	- `POINT_FADE_THRESHOLD_SIZE`: $(I `params`) is a single floating-point value that specifies the threshold value to which point sizes are clamped if they exceed the specified value. The default value is 1.0.
	
	- `POINT_SPRITE_COORD_ORIGIN`: $(I `params`) is a single enum specifying the point sprite texture coordinate origin, either `LOWER_LEFT` or `UPPER_LEFT`. The default value is `UPPER_LEFT`.
	
	Params:
	pname = Specifies a single-valued point parameter. `POINT_FADE_THRESHOLD_SIZE`, and `POINT_SPRITE_COORD_ORIGIN` are accepted.
	param = For $(REF pointParameterf) and $(REF pointParameteri), specifies the value that $(I `pname`) will be set to.
	*/
	void pointParameterf(Enum pname, Float param);
	
	/**
	The following values are accepted for $(I `pname`):
	
	- `POINT_FADE_THRESHOLD_SIZE`: $(I `params`) is a single floating-point value that specifies the threshold value to which point sizes are clamped if they exceed the specified value. The default value is 1.0.
	
	- `POINT_SPRITE_COORD_ORIGIN`: $(I `params`) is a single enum specifying the point sprite texture coordinate origin, either `LOWER_LEFT` or `UPPER_LEFT`. The default value is `UPPER_LEFT`.
	
	Params:
	pname = Specifies a single-valued point parameter. `POINT_FADE_THRESHOLD_SIZE`, and `POINT_SPRITE_COORD_ORIGIN` are accepted.
	params = For $(REF pointParameterfv) and $(REF pointParameteriv), specifies a pointer to an array where the value or values to be assigned to $(I `pname`) are stored.
	*/
	void pointParameterfv(Enum pname, const(Float)* params);
	
	/**
	The following values are accepted for $(I `pname`):
	
	- `POINT_FADE_THRESHOLD_SIZE`: $(I `params`) is a single floating-point value that specifies the threshold value to which point sizes are clamped if they exceed the specified value. The default value is 1.0.
	
	- `POINT_SPRITE_COORD_ORIGIN`: $(I `params`) is a single enum specifying the point sprite texture coordinate origin, either `LOWER_LEFT` or `UPPER_LEFT`. The default value is `UPPER_LEFT`.
	
	Params:
	pname = Specifies a single-valued point parameter. `POINT_FADE_THRESHOLD_SIZE`, and `POINT_SPRITE_COORD_ORIGIN` are accepted.
	param = For $(REF pointParameterf) and $(REF pointParameteri), specifies the value that $(I `pname`) will be set to.
	*/
	void pointParameteri(Enum pname, Int param);
	
	/**
	The following values are accepted for $(I `pname`):
	
	- `POINT_FADE_THRESHOLD_SIZE`: $(I `params`) is a single floating-point value that specifies the threshold value to which point sizes are clamped if they exceed the specified value. The default value is 1.0.
	
	- `POINT_SPRITE_COORD_ORIGIN`: $(I `params`) is a single enum specifying the point sprite texture coordinate origin, either `LOWER_LEFT` or `UPPER_LEFT`. The default value is `UPPER_LEFT`.
	
	Params:
	pname = Specifies a single-valued point parameter. `POINT_FADE_THRESHOLD_SIZE`, and `POINT_SPRITE_COORD_ORIGIN` are accepted.
	params = For $(REF pointParameterfv) and $(REF pointParameteriv), specifies a pointer to an array where the value or values to be assigned to $(I `pname`) are stored.
	*/
	void pointParameteriv(Enum pname, const(Int)* params);
	
	/**
	The `BLEND_COLOR` may be used to calculate the source and destination blending factors. The color components are clamped to the range [0, 1] before being stored. See $(REF blendFunc) for a complete description of the blending operations. Initially the `BLEND_COLOR` is set to (0, 0, 0, 0).
	
	Params:
	red = specify the components of `BLEND_COLOR`
	green = specify the components of `BLEND_COLOR`
	blue = specify the components of `BLEND_COLOR`
	alpha = specify the components of `BLEND_COLOR`
	*/
	void blendColor(Float red, Float green, Float blue, Float alpha);
	
	/**
	The blend equations determine how a new pixel (the ''source'' color) is combined with a pixel already in the framebuffer (the ''destination'' color). This function sets both the RGB blend equation and the alpha blend equation to a single equation. $(REF blendEquationi) specifies the blend equation for a single draw buffer whereas $(REF blendEquation) sets the blend equation for all draw buffers.
	
	These equations use the source and destination blend factors specified by either $(REF blendFunc) or $(REF blendFuncSeparate). See $(REF blendFunc) or $(REF blendFuncSeparate) for a description of the various blend factors.
	
	In the equations that follow, source and destination color components are referred to as (Rs, Gs, Bs, As) and (Rd, Gd, Bd, Ad), respectively. The result color is referred to as (Rr, Gr, Br, Ar). The source and destination blend factors are denoted (sR, sG, sB, sA) and (dR, dG, dB, dA), respectively. For these equations all color components are understood to have values in the range [0, 1].
	
	The results of these equations are clamped to the range [0, 1].
	
	The `MIN` and `MAX` equations are useful for applications that analyze image data (image thresholding against a constant color, for example). The `FUNC_ADD` equation is useful for antialiasing and transparency, among other things.
	
	Initially, both the RGB blend equation and the alpha blend equation are set to `FUNC_ADD`.
	
	Params:
	mode = specifies how source and destination colors are combined. It must be `FUNC_ADD`, `FUNC_SUBTRACT`, `FUNC_REVERSE_SUBTRACT`, `MIN`, `MAX`.
	*/
	void blendEquation(Enum mode);
	
	/**
	$(REF genQueries) returns $(I `n`) query object names in $(I `ids`). There is no guarantee that the names form a contiguous set of integers; however, it is guaranteed that none of the returned names was in use immediately before the call to $(REF genQueries).
	
	Query object names returned by a call to $(REF genQueries) are not returned by subsequent calls, unless they are first deleted with $(REF deleteQueries).
	
	No query objects are associated with the returned query object names until they are first used by calling $(REF beginQuery).
	
	Params:
	n = Specifies the number of query object names to be generated.
	ids = Specifies an array in which the generated query object names are stored.
	*/
	void genQueries(Sizei n, UInt* ids);
	
	/**
	$(REF deleteQueries) deletes $(I `n`) query objects named by the elements of the array $(I `ids`). After a query object is deleted, it has no contents, and its name is free for reuse (for example by $(REF genQueries)).
	
	$(REF deleteQueries) silently ignores 0's and names that do not correspond to existing query objects.
	
	Params:
	n = Specifies the number of query objects to be deleted.
	ids = Specifies an array of query objects to be deleted.
	*/
	void deleteQueries(Sizei n, const(UInt)* ids);
	
	/**
	$(REF isQuery) returns `TRUE` if $(I `id`) is currently the name of a query object. If $(I `id`) is zero, or is a non-zero value that is not currently the name of a query object, or if an error occurs, $(REF isQuery) returns `FALSE`.
	
	A name returned by $(REF genQueries), but not yet associated with a query object by calling $(REF beginQuery), is not the name of a query object.
	
	Params:
	id = Specifies a value that may be the name of a query object.
	*/
	Boolean isQuery(UInt id);
	
	/**
	$(REF beginQuery) and $(REF endQuery) delimit the boundaries of a query object. $(I `query`) must be a name previously returned from a call to $(REF genQueries). If a query object with name $(I `id`) does not yet exist it is created with the type determined by $(I `target`). $(I `target`) must be one of `SAMPLES_PASSED`, `ANY_SAMPLES_PASSED`, `PRIMITIVES_GENERATED`, `TRANSFORM_FEEDBACK_PRIMITIVES_WRITTEN`, or `TIME_ELAPSED`. The behavior of the query object depends on its type and is as follows.
	
	If $(I `target`) is `SAMPLES_PASSED`, $(I `id`) must be an unused name, or the name of an existing occlusion query object. When $(REF beginQuery) is executed, the query object's samples-passed counter is reset to 0. Subsequent rendering will increment the counter for every sample that passes the depth test. If the value of `SAMPLE_BUFFERS` is 0, then the samples-passed count is incremented by 1 for each fragment. If the value of `SAMPLE_BUFFERS` is 1, then the samples-passed count is incremented by the number of samples whose coverage bit is set. However, implementations, at their discression may instead increase the samples-passed count by the value of `SAMPLES` if any sample in the fragment is covered. When $(REF endQuery) is executed, the samples-passed counter is assigned to the query object's result value. This value can be queried by calling $(REF getQueryObject) with $(I `pname`) `QUERY_RESULT`.
	
	If $(I `target`) is `ANY_SAMPLES_PASSED` or `ANY_SAMPLES_PASSED_CONSERVATIVE`, $(I `id`) must be an unused name, or the name of an existing boolean occlusion query object. When $(REF beginQuery) is executed, the query object's samples-passed flag is reset to `FALSE`. Subsequent rendering causes the flag to be set to `TRUE` if any sample passes the depth test in the case of `ANY_SAMPLES_PASSED`, or if the implementation determines that any sample might pass the depth test in the case of `ANY_SAMPLES_PASSED_CONSERVATIVE`. The implementation may be able to provide a more efficient test in the case of `ANY_SAMPLES_PASSED_CONSERVATIVE` if some false positives are acceptable to the application. When $(REF endQuery) is executed, the samples-passed flag is assigned to the query object's result value. This value can be queried by calling $(REF getQueryObject) with $(I `pname`) `QUERY_RESULT`.
	
	If $(I `target`) is `PRIMITIVES_GENERATED`, $(I `id`) must be an unused name, or the name of an existing primitive query object previously bound to the `PRIMITIVES_GENERATED` query binding. When $(REF beginQuery) is executed, the query object's primitives-generated counter is reset to 0. Subsequent rendering will increment the counter once for every vertex that is emitted from the geometry shader, or from the vertex shader if no geometry shader is present. When $(REF endQuery) is executed, the primitives-generated counter is assigned to the query object's result value. This value can be queried by calling $(REF getQueryObject) with $(I `pname`) `QUERY_RESULT`.
	
	If $(I `target`) is `TRANSFORM_FEEDBACK_PRIMITIVES_WRITTEN`, $(I `id`) must be an unused name, or the name of an existing primitive query object previously bound to the `TRANSFORM_FEEDBACK_PRIMITIVES_WRITTEN` query binding. When $(REF beginQuery) is executed, the query object's primitives-written counter is reset to 0. Subsequent rendering will increment the counter once for every vertex that is written into the bound transform feedback buffer(s). If transform feedback mode is not activated between the call to $(REF beginQuery) and $(REF endQuery), the counter will not be incremented. When $(REF endQuery) is executed, the primitives-written counter is assigned to the query object's result value. This value can be queried by calling $(REF getQueryObject) with $(I `pname`) `QUERY_RESULT`.
	
	If $(I `target`) is `TIME_ELAPSED`, $(I `id`) must be an unused name, or the name of an existing timer query object previously bound to the `TIME_ELAPSED` query binding. When $(REF beginQuery) is executed, the query object's time counter is reset to 0. When $(REF endQuery) is executed, the elapsed server time that has passed since the call to $(REF beginQuery) is written into the query object's time counter. This value can be queried by calling $(REF getQueryObject) with $(I `pname`) `QUERY_RESULT`.
	
	Querying the `QUERY_RESULT` implicitly flushes the GL pipeline until the rendering delimited by the query object has completed and the result is available. `QUERY_RESULT_AVAILABLE` can be queried to determine if the result is immediately available or if the rendering is not yet complete.
	
	Params:
	target = Specifies the target type of query object established between $(REF beginQuery) and the subsequent $(REF endQuery). The symbolic constant must be one of `SAMPLES_PASSED`, `ANY_SAMPLES_PASSED`, `ANY_SAMPLES_PASSED_CONSERVATIVE`, `PRIMITIVES_GENERATED`, `TRANSFORM_FEEDBACK_PRIMITIVES_WRITTEN`, or `TIME_ELAPSED`.
	id = Specifies the name of a query object.
	*/
	void beginQuery(Enum target, UInt id);
	
	/**
	$(REF beginQuery) and $(REF endQuery) delimit the boundaries of a query object. $(I `query`) must be a name previously returned from a call to $(REF genQueries). If a query object with name $(I `id`) does not yet exist it is created with the type determined by $(I `target`). $(I `target`) must be one of `SAMPLES_PASSED`, `ANY_SAMPLES_PASSED`, `PRIMITIVES_GENERATED`, `TRANSFORM_FEEDBACK_PRIMITIVES_WRITTEN`, or `TIME_ELAPSED`. The behavior of the query object depends on its type and is as follows.
	
	If $(I `target`) is `SAMPLES_PASSED`, $(I `id`) must be an unused name, or the name of an existing occlusion query object. When $(REF beginQuery) is executed, the query object's samples-passed counter is reset to 0. Subsequent rendering will increment the counter for every sample that passes the depth test. If the value of `SAMPLE_BUFFERS` is 0, then the samples-passed count is incremented by 1 for each fragment. If the value of `SAMPLE_BUFFERS` is 1, then the samples-passed count is incremented by the number of samples whose coverage bit is set. However, implementations, at their discression may instead increase the samples-passed count by the value of `SAMPLES` if any sample in the fragment is covered. When $(REF endQuery) is executed, the samples-passed counter is assigned to the query object's result value. This value can be queried by calling $(REF getQueryObject) with $(I `pname`) `QUERY_RESULT`.
	
	If $(I `target`) is `ANY_SAMPLES_PASSED` or `ANY_SAMPLES_PASSED_CONSERVATIVE`, $(I `id`) must be an unused name, or the name of an existing boolean occlusion query object. When $(REF beginQuery) is executed, the query object's samples-passed flag is reset to `FALSE`. Subsequent rendering causes the flag to be set to `TRUE` if any sample passes the depth test in the case of `ANY_SAMPLES_PASSED`, or if the implementation determines that any sample might pass the depth test in the case of `ANY_SAMPLES_PASSED_CONSERVATIVE`. The implementation may be able to provide a more efficient test in the case of `ANY_SAMPLES_PASSED_CONSERVATIVE` if some false positives are acceptable to the application. When $(REF endQuery) is executed, the samples-passed flag is assigned to the query object's result value. This value can be queried by calling $(REF getQueryObject) with $(I `pname`) `QUERY_RESULT`.
	
	If $(I `target`) is `PRIMITIVES_GENERATED`, $(I `id`) must be an unused name, or the name of an existing primitive query object previously bound to the `PRIMITIVES_GENERATED` query binding. When $(REF beginQuery) is executed, the query object's primitives-generated counter is reset to 0. Subsequent rendering will increment the counter once for every vertex that is emitted from the geometry shader, or from the vertex shader if no geometry shader is present. When $(REF endQuery) is executed, the primitives-generated counter is assigned to the query object's result value. This value can be queried by calling $(REF getQueryObject) with $(I `pname`) `QUERY_RESULT`.
	
	If $(I `target`) is `TRANSFORM_FEEDBACK_PRIMITIVES_WRITTEN`, $(I `id`) must be an unused name, or the name of an existing primitive query object previously bound to the `TRANSFORM_FEEDBACK_PRIMITIVES_WRITTEN` query binding. When $(REF beginQuery) is executed, the query object's primitives-written counter is reset to 0. Subsequent rendering will increment the counter once for every vertex that is written into the bound transform feedback buffer(s). If transform feedback mode is not activated between the call to $(REF beginQuery) and $(REF endQuery), the counter will not be incremented. When $(REF endQuery) is executed, the primitives-written counter is assigned to the query object's result value. This value can be queried by calling $(REF getQueryObject) with $(I `pname`) `QUERY_RESULT`.
	
	If $(I `target`) is `TIME_ELAPSED`, $(I `id`) must be an unused name, or the name of an existing timer query object previously bound to the `TIME_ELAPSED` query binding. When $(REF beginQuery) is executed, the query object's time counter is reset to 0. When $(REF endQuery) is executed, the elapsed server time that has passed since the call to $(REF beginQuery) is written into the query object's time counter. This value can be queried by calling $(REF getQueryObject) with $(I `pname`) `QUERY_RESULT`.
	
	Querying the `QUERY_RESULT` implicitly flushes the GL pipeline until the rendering delimited by the query object has completed and the result is available. `QUERY_RESULT_AVAILABLE` can be queried to determine if the result is immediately available or if the rendering is not yet complete.
	
	Params:
	target = Specifies the target type of query object established between $(REF beginQuery) and the subsequent $(REF endQuery). The symbolic constant must be one of `SAMPLES_PASSED`, `ANY_SAMPLES_PASSED`, `ANY_SAMPLES_PASSED_CONSERVATIVE`, `PRIMITIVES_GENERATED`, `TRANSFORM_FEEDBACK_PRIMITIVES_WRITTEN`, or `TIME_ELAPSED`.
	*/
	void endQuery(Enum target);
	
	/**
	$(REF getQueryiv) returns in $(I `params`) a selected parameter of the query object target specified by $(I `target`).
	
	$(I `pname`) names a specific query object target parameter. When $(I `pname`) is `CURRENT_QUERY`, the name of the currently active query for $(I `target`), or zero if no query is active, will be placed in $(I `params`). If $(I `pname`) is `QUERY_COUNTER_BITS`, the implementation-dependent number of bits used to hold the result of queries for $(I `target`) is returned in $(I `params`).
	
	Params:
	target = Specifies a query object target. Must be `SAMPLES_PASSED`, `ANY_SAMPLES_PASSED`, `ANY_SAMPLES_PASSED_CONSERVATIVE` `PRIMITIVES_GENERATED`, `TRANSFORM_FEEDBACK_PRIMITIVES_WRITTEN`, `TIME_ELAPSED`, or `TIMESTAMP`.
	pname = Specifies the symbolic name of a query object target parameter. Accepted values are `CURRENT_QUERY` or `QUERY_COUNTER_BITS`.
	params = Returns the requested data.
	*/
	void getQueryiv(Enum target, Enum pname, Int* params);
	
	/**
	These commands return a selected parameter of the query object specified by $(I `id`). $(REF getQueryObject) returns in $(I `params`) a selected parameter of the query object specified by $(I `id`). $(REF getQueryBufferObject) returns in $(I `buffer`) a selected parameter of the query object specified by $(I `id`), by writing it to $(I `buffer`)'s data store at the byte offset specified by $(I `offset`).
	
	$(I `pname`) names a specific query object parameter. $(I `pname`) can be as follows:
	
	- `QUERY_RESULT`: $(I `params`) or $(I `buffer`) returns the value of the query object's passed samples counter. The initial value is 0.
	
	- `QUERY_RESULT_NO_WAIT`: If the result of the query is available (that is, a query of `QUERY_RESULT_AVAILABLE` would return non-zero), then $(I `params`) or $(I `buffer`) returns the value of the query object's passed samples counter, otherwise, the data referred to by $(I `params`) or $(I `buffer`) is not modified. The initial value is 0.
	
	- `QUERY_RESULT_AVAILABLE`: $(I `params`) or $(I `buffer`) returns whether the passed samples counter is immediately available. If a delay would occur waiting for the query result, `FALSE` is returned. Otherwise, `TRUE` is returned, which also indicates that the results of all previous queries are available as well.
	
	Params:
	id = Specifies the name of a query object.
	pname = Specifies the symbolic name of a query object parameter. Accepted values are `QUERY_RESULT` or `QUERY_RESULT_AVAILABLE`.
	params = If a buffer is bound to the `QUERY_RESULT_BUFFER` target, then $(I `params`) is treated as an offset to a location within that buffer's data store to receive the result of the query. If no buffer is bound to `QUERY_RESULT_BUFFER`, then $(I `params`) is treated as an address in client memory of a variable to receive the resulting data.
	*/
	void getQueryObjectiv(UInt id, Enum pname, Int* params);
	
	/**
	These commands return a selected parameter of the query object specified by $(I `id`). $(REF getQueryObject) returns in $(I `params`) a selected parameter of the query object specified by $(I `id`). $(REF getQueryBufferObject) returns in $(I `buffer`) a selected parameter of the query object specified by $(I `id`), by writing it to $(I `buffer`)'s data store at the byte offset specified by $(I `offset`).
	
	$(I `pname`) names a specific query object parameter. $(I `pname`) can be as follows:
	
	- `QUERY_RESULT`: $(I `params`) or $(I `buffer`) returns the value of the query object's passed samples counter. The initial value is 0.
	
	- `QUERY_RESULT_NO_WAIT`: If the result of the query is available (that is, a query of `QUERY_RESULT_AVAILABLE` would return non-zero), then $(I `params`) or $(I `buffer`) returns the value of the query object's passed samples counter, otherwise, the data referred to by $(I `params`) or $(I `buffer`) is not modified. The initial value is 0.
	
	- `QUERY_RESULT_AVAILABLE`: $(I `params`) or $(I `buffer`) returns whether the passed samples counter is immediately available. If a delay would occur waiting for the query result, `FALSE` is returned. Otherwise, `TRUE` is returned, which also indicates that the results of all previous queries are available as well.
	
	Params:
	id = Specifies the name of a query object.
	pname = Specifies the symbolic name of a query object parameter. Accepted values are `QUERY_RESULT` or `QUERY_RESULT_AVAILABLE`.
	params = If a buffer is bound to the `QUERY_RESULT_BUFFER` target, then $(I `params`) is treated as an offset to a location within that buffer's data store to receive the result of the query. If no buffer is bound to `QUERY_RESULT_BUFFER`, then $(I `params`) is treated as an address in client memory of a variable to receive the resulting data.
	*/
	void getQueryObjectuiv(UInt id, Enum pname, UInt* params);
	
	/**
	$(REF bindBuffer) binds a buffer object to the specified buffer binding point. Calling $(REF bindBuffer) with $(I `target`) set to one of the accepted symbolic constants and $(I `buffer`) set to the name of a buffer object binds that buffer object name to the target. If no buffer object with name $(I `buffer`) exists, one is created with that name. When a buffer object is bound to a target, the previous binding for that target is automatically broken.
	
	Buffer object names are unsigned integers. The value zero is reserved, but there is no default buffer object for each buffer object target. Instead, $(I `buffer`) set to zero effectively unbinds any buffer object previously bound, and restores client memory usage for that buffer object target (if supported for that target). Buffer object names and the corresponding buffer object contents are local to the shared object space of the current GL rendering context; two rendering contexts share buffer object names only if they explicitly enable sharing between contexts through the appropriate GL windows interfaces functions.
	
	$(REF genBuffers) must be used to generate a set of unused buffer object names.
	
	The state of a buffer object immediately after it is first bound is an unmapped zero-sized memory buffer with `READ_WRITE` access and `STATIC_DRAW` usage.
	
	While a non-zero buffer object name is bound, GL operations on the target to which it is bound affect the bound buffer object, and queries of the target to which it is bound return state from the bound buffer object. While buffer object name zero is bound, as in the initial state, attempts to modify or query state on the target to which it is bound generates an `INVALID_OPERATION` error.
	
	When a non-zero buffer object is bound to the `ARRAY_BUFFER` target, the vertex array pointer parameter is interpreted as an offset within the buffer object measured in basic machine units.
	
	When a non-zero buffer object is bound to the `DRAW_INDIRECT_BUFFER` target, parameters for draws issued through $(REF drawArraysIndirect) and $(REF drawElementsIndirect) are sourced from the specified offset in that buffer object's data store.
	
	When a non-zero buffer object is bound to the `DISPATCH_INDIRECT_BUFFER` target, the parameters for compute dispatches issued through $(REF dispatchComputeIndirect) are sourced from the specified offset in that buffer object's data store.
	
	While a non-zero buffer object is bound to the `ELEMENT_ARRAY_BUFFER` target, the indices parameter of $(REF drawElements), $(REF drawElementsInstanced), $(REF drawElementsBaseVertex), $(REF drawRangeElements), $(REF drawRangeElementsBaseVertex), $(REF multiDrawElements), or $(REF multiDrawElementsBaseVertex) is interpreted as an offset within the buffer object measured in basic machine units.
	
	While a non-zero buffer object is bound to the `PIXEL_PACK_BUFFER` target, the following commands are affected: $(REF getCompressedTexImage), $(REF getTexImage), and $(REF readPixels). The pointer parameter is interpreted as an offset within the buffer object measured in basic machine units.
	
	While a non-zero buffer object is bound to the `PIXEL_UNPACK_BUFFER` target, the following commands are affected: $(REF compressedTexImage1D), $(REF compressedTexImage2D), $(REF compressedTexImage3D), $(REF compressedTexSubImage1D), $(REF compressedTexSubImage2D), $(REF compressedTexSubImage3D), $(REF texImage1D), $(REF texImage2D), $(REF texImage3D), $(REF texSubImage1D), $(REF texSubImage2D), and $(REF texSubImage3D). The pointer parameter is interpreted as an offset within the buffer object measured in basic machine units.
	
	The buffer targets `COPY_READ_BUFFER` and `COPY_WRITE_BUFFER` are provided to allow $(REF copyBufferSubData) to be used without disturbing the state of other bindings. However, $(REF copyBufferSubData) may be used with any pair of buffer binding points.
	
	The `TRANSFORM_FEEDBACK_BUFFER` buffer binding point may be passed to $(REF bindBuffer), but will not directly affect transform feedback state. Instead, the indexed `TRANSFORM_FEEDBACK_BUFFER` bindings must be used through a call to $(REF bindBufferBase) or $(REF bindBufferRange). This will affect the generic `TRANSFORM_FEEDBACK_BUFFER` binding.
	
	Likewise, the `UNIFORM_BUFFER`, `ATOMIC_COUNTER_BUFFER` and `SHADER_STORAGE_BUFFER` buffer binding points may be used, but do not directly affect uniform buffer, atomic counter buffer or shader storage buffer state, respectively. $(REF bindBufferBase) or $(REF bindBufferRange) must be used to bind a buffer to an indexed uniform buffer, atomic counter buffer or shader storage buffer binding point.
	
	The `QUERY_BUFFER` binding point is used to specify a buffer object that is to receive the results of query objects through calls to the $(REF getQueryObject) family of commands.
	
	A buffer object binding created with $(REF bindBuffer) remains active until a different buffer object name is bound to the same target, or until the bound buffer object is deleted with $(REF deleteBuffers).
	
	Once created, a named buffer object may be re-bound to any target as often as needed. However, the GL implementation may make choices about how to optimize the storage of a buffer object based on its initial binding target.
	
	Params:
	target = Specifies the target to which the buffer object is bound, which must be one of the buffer binding targets in the following table:
	buffer = Specifies the name of a buffer object.
	*/
	void bindBuffer(Enum target, UInt buffer);
	
	/**
	$(REF deleteBuffers) deletes $(I `n`) buffer objects named by the elements of the array $(I `buffers`). After a buffer object is deleted, it has no contents, and its name is free for reuse (for example by $(REF genBuffers)). If a buffer object that is currently bound is deleted, the binding reverts to 0 (the absence of any buffer object).
	
	$(REF deleteBuffers) silently ignores 0's and names that do not correspond to existing buffer objects.
	
	Params:
	n = Specifies the number of buffer objects to be deleted.
	buffers = Specifies an array of buffer objects to be deleted.
	*/
	void deleteBuffers(Sizei n, const(UInt)* buffers);
	
	/**
	$(REF genBuffers) returns $(I `n`) buffer object names in $(I `buffers`). There is no guarantee that the names form a contiguous set of integers; however, it is guaranteed that none of the returned names was in use immediately before the call to $(REF genBuffers).
	
	Buffer object names returned by a call to $(REF genBuffers) are not returned by subsequent calls, unless they are first deleted with $(REF deleteBuffers).
	
	No buffer objects are associated with the returned buffer object names until they are first bound by calling $(REF bindBuffer).
	
	Params:
	n = Specifies the number of buffer object names to be generated.
	buffers = Specifies an array in which the generated buffer object names are stored.
	*/
	void genBuffers(Sizei n, UInt* buffers);
	
	/**
	$(REF isBuffer) returns `TRUE` if $(I `buffer`) is currently the name of a buffer object. If $(I `buffer`) is zero, or is a non-zero value that is not currently the name of a buffer object, or if an error occurs, $(REF isBuffer) returns `FALSE`.
	
	A name returned by $(REF genBuffers), but not yet associated with a buffer object by calling $(REF bindBuffer), is not the name of a buffer object.
	
	Params:
	buffer = Specifies a value that may be the name of a buffer object.
	*/
	Boolean isBuffer(UInt buffer);
	
	/**
	$(REF bufferData) and $(REF namedBufferData) create a new data store for a buffer object. In case of $(REF bufferData), the buffer object currently bound to $(I `target`) is used. For $(REF namedBufferData), a buffer object associated with ID specified by the caller in $(I `buffer`) will be used instead.
	
	While creating the new storage, any pre-existing data store is deleted. The new data store is created with the specified $(I `size`) in bytes and $(I `usage`). If $(I `data`) is not `NULL`, the data store is initialized with data from this pointer. In its initial state, the new data store is not mapped, it has a `NULL` mapped pointer, and its mapped access is `READ_WRITE`.
	
	$(I `usage`) is a hint to the GL implementation as to how a buffer object's data store will be accessed. This enables the GL implementation to make more intelligent decisions that may significantly impact buffer object performance. It does not, however, constrain the actual usage of the data store. $(I `usage`) can be broken down into two parts: first, the frequency of access (modification and usage), and second, the nature of that access. The frequency of access may be one of these:
	
	- STREAM: The data store contents will be modified once and used at most a few times.
	
	- STATIC: The data store contents will be modified once and used many times.
	
	- DYNAMIC: The data store contents will be modified repeatedly and used many times.
	
	The nature of access may be one of these:
	
	- DRAW: The data store contents are modified by the application, and used as the source for GL drawing and image specification commands.
	
	- READ: The data store contents are modified by reading data from the GL, and used to return that data when queried by the application.
	
	- COPY: The data store contents are modified by reading data from the GL, and used as the source for GL drawing and image specification commands.
	
	Params:
	target = Specifies the target to which the buffer object is bound for $(REF bufferData), which must be one of the buffer binding targets in the following table:
	size = Specifies the size in bytes of the buffer object's new data store.
	data = Specifies a pointer to data that will be copied into the data store for initialization, or `NULL` if no data is to be copied.
	usage = Specifies the expected usage pattern of the data store. The symbolic constant must be `STREAM_DRAW`, `STREAM_READ`, `STREAM_COPY`, `STATIC_DRAW`, `STATIC_READ`, `STATIC_COPY`, `DYNAMIC_DRAW`, `DYNAMIC_READ`, or `DYNAMIC_COPY`.
	*/
	void bufferData(Enum target, SizeiPtr size, const(void)* data, Enum usage);
	
	/**
	$(REF bufferSubData) and $(REF namedBufferSubData) redefine some or all of the data store for the specified buffer object. Data starting at byte offset $(I `offset`) and extending for $(I `size`) bytes is copied to the data store from the memory pointed to by $(I `data`). $(I `offset`) and $(I `size`) must define a range lying entirely within the buffer object's data store.
	
	Params:
	target = Specifies the target to which the buffer object is bound for $(REF bufferSubData), which must be one of the buffer binding targets in the following table:
	offset = Specifies the offset into the buffer object's data store where data replacement will begin, measured in bytes.
	size = Specifies the size in bytes of the data store region being replaced.
	data = Specifies a pointer to the new data that will be copied into the data store.
	*/
	void bufferSubData(Enum target, IntPtr offset, SizeiPtr size, const(void)* data);
	
	/**
	$(REF getBufferSubData) and $(REF getNamedBufferSubData) return some or all of the data contents of the data store of the specified buffer object. Data starting at byte offset $(I `offset`) and extending for $(I `size`) bytes is copied from the buffer object's data store to the memory pointed to by $(I `data`). An error is thrown if the buffer object is currently mapped, or if $(I `offset`) and $(I `size`) together define a range beyond the bounds of the buffer object's data store.
	
	Params:
	target = Specifies the target to which the buffer object is bound for $(REF getBufferSubData), which must be one of the buffer binding targets in the following table:
	offset = Specifies the offset into the buffer object's data store from which data will be returned, measured in bytes.
	size = Specifies the size in bytes of the data store region being returned.
	data = Specifies a pointer to the location where buffer object data is returned.
	*/
	void getBufferSubData(Enum target, IntPtr offset, SizeiPtr size, void* data);
	
	/**
	$(REF mapBuffer) and $(REF mapNamedBuffer) map the entire data store of a specified buffer object into the client's address space. The data can then be directly read and/or written relative to the returned pointer, depending on the specified $(I `access`) policy.
	
	A pointer to the beginning of the mapped range is returned once all pending operations on that buffer object have completed, and may be used to modify and/or query the corresponding range of the data store according to the value of $(I `access`):
	
	If an error is generated, a `NULL` pointer is returned.
	
	If no error occurs, the returned pointer will reflect an allocation aligned to the value of `MIN_MAP_BUFFER_ALIGNMENT` basic machine units.
	
	The returned pointer values may not be passed as parameter values to GL commands. For example, they may not be used to specify array pointers, or to specify or query pixel or texture image data; such actions produce undefined results, although implementations may not check for such behavior for performance reasons.
	
	No GL error is generated if the returned pointer is accessed in a way inconsistent with $(I `access`) (e.g. used to read from a mapping made with $(I `access`) `WRITE_ONLY` or write to a mapping made with $(I `access`) `READ_ONLY`), but the result is undefined and system errors (possibly including program termination) may occur.
	
	Mappings to the data stores of buffer objects may have nonstandard performance characteristics. For example, such mappings may be marked as uncacheable regions of memory, and in such cases reading from them may be very slow. To ensure optimal performance, the client should use the mapping in a fashion consistent with the values of `BUFFER_USAGE` for the buffer object and of $(I `access`). Using a mapping in a fashion inconsistent with these values is liable to be multiple orders of magnitude slower than using normal memory.
	
	Params:
	target = Specifies the target to which the buffer object is bound for $(REF mapBuffer), which must be one of the buffer binding targets in the following table:
	access = Specifies the access policy for $(REF mapBuffer) and $(REF mapNamedBuffer), indicating whether it will be possible to read from, write to, or both read from and write to the buffer object's mapped data store. The symbolic constant must be `READ_ONLY`, `WRITE_ONLY`, or `READ_WRITE`.
	*/
	void* mapBuffer(Enum target, Enum access);
	
	/**
	$(REF unmapBuffer) and $(REF unmapNamedBuffer) unmap (release) any mapping of a specified buffer object into the client's address space (see $(REF mapBufferRange) and $(REF mapBuffer)).
	
	If a mapping is not unmapped before the corresponding buffer object's data store is used by the GL, an error will be generated by any GL command that attempts to dereference the buffer object's data store, unless the buffer was successfully mapped with `MAP_PERSISTENT_BIT` (see $(REF mapBufferRange)). When a data store is unmapped, the mapped pointer becomes invalid.
	
	$(REF unmapBuffer) returns `TRUE` unless the data store contents have become corrupt during the time the data store was mapped. This can occur for system-specific reasons that affect the availability of graphics memory, such as screen mode changes. In such situations, `FALSE` is returned and the data store contents are undefined. An application must detect this rare condition and reinitialize the data store.
	
	A buffer object's mapped data store is automatically unmapped when the buffer object is deleted or its data store is recreated with $(REF bufferData)).
	
	Params:
	target = Specifies the target to which the buffer object is bound for $(REF unmapBuffer), which must be one of the buffer binding targets in the following table:
	*/
	Boolean unmapBuffer(Enum target);
	
	/**
	These functions return in $(I `data`) a selected parameter of the specified buffer object.
	
	$(I `pname`) names a specific buffer object parameter, as follows:
	
	- `BUFFER_ACCESS`: $(I `params`) returns the access policy set while mapping the buffer object (the value of the $(I `access`) parameter enum passed to $(REF mapBuffer)). If the buffer was mapped with $(REF mapBufferRange), the access policy is determined by translating the bits in that $(I `access`) parameter to one of the supported enums for $(REF mapBuffer) as described in the OpenGL Specification.
	
	- `BUFFER_ACCESS_FLAGS`: $(I `params`) returns the access policy set while mapping the buffer object (the value of the $(I `access`) parameter bitfield passed to $(REF mapBufferRange)). If the buffer was mapped with $(REF mapBuffer), the access policy is determined by translating the enums in that $(I `access`) parameter to the corresponding bits for $(REF mapBufferRange) as described in the OpenGL Specification. The initial value is zero.
	
	- `BUFFER_IMMUTABLE_STORAGE`: $(I `params`) returns a boolean flag indicating whether the buffer object is immutable. The initial value is `FALSE`.
	
	- `BUFFER_MAPPED`: $(I `params`) returns a flag indicating whether the buffer object is currently mapped. The initial value is `FALSE`.
	
	- `BUFFER_MAP_LENGTH`: $(I `params`) returns the length of the mapping into the buffer object established with $(REF mapBuffer*). The `i64v` versions of these queries should be used for this parameter. The initial value is zero.
	
	- `BUFFER_MAP_OFFSET`: $(I `params`) returns the offset of the mapping into the buffer object established with $(REF mapBuffer*). The `i64v` versions of these queries should be used for this parameter. The initial value is zero.
	
	- `BUFFER_SIZE`: $(I `params`) returns the size of the buffer object, measured in bytes. The initial value is 0.
	
	- `BUFFER_STORAGE_FLAGS`: $(I `params`) returns a bitfield indicating the storage flags for the buffer object. If the buffer object is immutable, the value returned will be that specified when the data store was established with $(REF bufferStorage). If the data store was established with $(REF bufferData), the value will be `MAP_READ_BIT` | `MAP_WRITE_BIT` | `DYNAMIC_STORAGE_BIT` | `MAP_WRITE_BIT`. The initial value is zero.
	
	- `BUFFER_USAGE`: $(I `params`) returns the buffer object's usage pattern. The initial value is `STATIC_DRAW`.
	
	Params:
	target = Specifies the target to which the buffer object is bound for $(REF getBufferParameteriv) and $(REF getBufferParameteri64v). Must be one of the buffer binding targets in the following table:
	value = Specifies the name of the buffer object parameter to query.
	data = Returns the requested parameter.
	*/
	void getBufferParameteriv(Enum target, Enum value, Int* data);
	
	/**
	$(REF getBufferPointerv) and $(REF getNamedBufferPointerv) return the buffer pointer $(I `pname`), which must be `BUFFER_MAP_POINTER`. The single buffer map pointer is returned in $(I `params`). A `NULL` pointer is returned if the buffer object's data store is not currently mapped; or if the requesting context did not map the buffer object's data store, and the implementation is unable to support mappings on multiple clients.
	
	Params:
	target = Specifies the target to which the buffer object is bound for $(REF getBufferPointerv), which must be one of the buffer binding targets in the following table:
	pname = Specifies the name of the pointer to be returned. Must be `BUFFER_MAP_POINTER`.
	params = Returns the pointer value specified by $(I `pname`).
	*/
	void getBufferPointerv(Enum target, Enum pname, void* params);
	
	/**
	The blend equations determines how a new pixel (the ''source'' color) is combined with a pixel already in the framebuffer (the ''destination'' color). These functions specify one blend equation for the RGB-color components and one blend equation for the alpha component. $(REF blendEquationSeparatei) specifies the blend equations for a single draw buffer whereas $(REF blendEquationSeparate) sets the blend equations for all draw buffers.
	
	The blend equations use the source and destination blend factors specified by either $(REF blendFunc) or $(REF blendFuncSeparate). See $(REF blendFunc) or $(REF blendFuncSeparate) for a description of the various blend factors.
	
	In the equations that follow, source and destination color components are referred to as (Rs, Gs, Bs, As) and (Rd, Gd, Bd, Ad), respectively. The result color is referred to as (Rr, Gr, Br, Ar). The source and destination blend factors are denoted (sR, sG, sB, sA) and (dR, dG, dB, dA), respectively. For these equations all color components are understood to have values in the range [0, 1].
	
	The results of these equations are clamped to the range [0, 1].
	
	The `MIN` and `MAX` equations are useful for applications that analyze image data (image thresholding against a constant color, for example). The `FUNC_ADD` equation is useful for antialiasing and transparency, among other things.
	
	Initially, both the RGB blend equation and the alpha blend equation are set to `FUNC_ADD`.
	
	Params:
	modeRGB = specifies the RGB blend equation, how the red, green, and blue components of the source and destination colors are combined. It must be `FUNC_ADD`, `FUNC_SUBTRACT`, `FUNC_REVERSE_SUBTRACT`, `MIN`, `MAX`.
	modeAlpha = specifies the alpha blend equation, how the alpha component of the source and destination colors are combined. It must be `FUNC_ADD`, `FUNC_SUBTRACT`, `FUNC_REVERSE_SUBTRACT`, `MIN`, `MAX`.
	*/
	void blendEquationSeparate(Enum modeRGB, Enum modeAlpha);
	
	/**
	$(REF drawBuffers) and $(REF namedFramebufferDrawBuffers) define an array of buffers into which outputs from the fragment shader data will be written. If a fragment shader writes a value to one or more user defined output variables, then the value of each variable will be written into the buffer specified at a location within $(I `bufs`) corresponding to the location assigned to that user defined output. The draw buffer used for user defined outputs assigned to locations greater than or equal to $(I `n`) is implicitly set to `NONE` and any data written to such an output is discarded.
	
	For $(REF drawBuffers), the framebuffer object that is bound to the `DRAW_FRAMEBUFFER` binding will be used. For $(REF namedFramebufferDrawBuffers), $(I `framebuffer`) is the name of the framebuffer object. If $(I `framebuffer`) is zero, then the default framebuffer is affected.
	
	The symbolic constants contained in $(I `bufs`) may be any of the following:
	
	- `NONE`: The fragment shader output value is not written into any color buffer.
	
	- `FRONT_LEFT`: The fragment shader output value is written into the front left color buffer.
	
	- `FRONT_RIGHT`: The fragment shader output value is written into the front right color buffer.
	
	- `BACK_LEFT`: The fragment shader output value is written into the back left color buffer.
	
	- `BACK_RIGHT`: The fragment shader output value is written into the back right color buffer.
	
	- `COLOR_ATTACHMENT`  $(I n): The fragment shader output value is written into the $(I n)th color attachment of the current framebuffer. $(I n) may range from zero to the value of `MAX_COLOR_ATTACHMENTS`.
	
	Except for `NONE`, the preceding symbolic constants may not appear more than once in $(I `bufs`). The maximum number of draw buffers supported is implementation dependent and can be queried by calling $(REF get) with the argument `MAX_DRAW_BUFFERS`.
	
	Params:
	n = Specifies the number of buffers in $(I `bufs`).
	bufs = Points to an array of symbolic constants specifying the buffers into which fragment colors or data values will be written.
	*/
	void drawBuffers(Sizei n, const(Enum)* bufs);
	
	/**
	Stenciling, like depth-buffering, enables and disables drawing on a per-pixel basis. You draw into the stencil planes using GL drawing primitives, then render geometry and images, using the stencil planes to mask out portions of the screen. Stenciling is typically used in multipass rendering algorithms to achieve special effects, such as decals, outlining, and constructive solid geometry rendering.
	
	The stencil test conditionally eliminates a pixel based on the outcome of a comparison between the value in the stencil buffer and a reference value. To enable and disable the test, call $(REF enable) and $(REF disable) with argument `STENCIL_TEST`; to control it, call $(REF stencilFunc) or $(REF stencilFuncSeparate).
	
	There can be two separate sets of $(I `sfail`), $(I `dpfail`), and $(I `dppass`) parameters; one affects back-facing polygons, and the other affects front-facing polygons as well as other non-polygon primitives. $(REF stencilOp) sets both front and back stencil state to the same values, as if $(REF stencilOpSeparate) were called with $(I `face`) set to `FRONT_AND_BACK`.
	
	$(REF stencilOpSeparate) takes three arguments that indicate what happens to the stored stencil value while stenciling is enabled. If the stencil test fails, no change is made to the pixel's color or depth buffers, and $(I `sfail`) specifies what happens to the stencil buffer contents. The following eight actions are possible.
	
	- `KEEP`: Keeps the current value.
	
	- `ZERO`: Sets the stencil buffer value to 0.
	
	- `REPLACE`: Sets the stencil buffer value to $(I ref), as specified by $(REF stencilFunc).
	
	- `INCR`: Increments the current stencil buffer value. Clamps to the maximum representable unsigned value.
	
	- `INCR_WRAP`: Increments the current stencil buffer value. Wraps stencil buffer value to zero when incrementing the maximum representable unsigned value.
	
	- `DECR`: Decrements the current stencil buffer value. Clamps to 0.
	
	- `DECR_WRAP`: Decrements the current stencil buffer value. Wraps stencil buffer value to the maximum representable unsigned value when decrementing a stencil buffer value of zero.
	
	- `INVERT`: Bitwise inverts the current stencil buffer value.
	
	Stencil buffer values are treated as unsigned integers. When incremented and decremented, values are clamped to 0 and 2n - 1, where n is the value returned by querying `STENCIL_BITS`.
	
	The other two arguments to $(REF stencilOpSeparate) specify stencil buffer actions that depend on whether subsequent depth buffer tests succeed ($(I `dppass`)) or fail ($(I `dpfail`)) (see $(REF depthFunc)). The actions are specified using the same eight symbolic constants as $(I `sfail`). Note that $(I `dpfail`) is ignored when there is no depth buffer, or when the depth buffer is not enabled. In these cases, $(I `sfail`) and $(I `dppass`) specify stencil action when the stencil test fails and passes, respectively.
	
	Params:
	face = Specifies whether front and/or back stencil state is updated. Three symbolic constants are valid: `FRONT`, `BACK`, and `FRONT_AND_BACK`.
	sfail = Specifies the action to take when the stencil test fails. Eight symbolic constants are accepted: `KEEP`, `ZERO`, `REPLACE`, `INCR`, `INCR_WRAP`, `DECR`, `DECR_WRAP`, and `INVERT`. The initial value is `KEEP`.
	dpfail = Specifies the stencil action when the stencil test passes, but the depth test fails. $(I `dpfail`) accepts the same symbolic constants as $(I `sfail`). The initial value is `KEEP`.
	dppass = Specifies the stencil action when both the stencil test and the depth test pass, or when the stencil test passes and either there is no depth buffer or depth testing is not enabled. $(I `dppass`) accepts the same symbolic constants as $(I `sfail`). The initial value is `KEEP`.
	*/
	void stencilOpSeparate(Enum face, Enum sfail, Enum dpfail, Enum dppass);
	
	/**
	Stenciling, like depth-buffering, enables and disables drawing on a per-pixel basis. You draw into the stencil planes using GL drawing primitives, then render geometry and images, using the stencil planes to mask out portions of the screen. Stenciling is typically used in multipass rendering algorithms to achieve special effects, such as decals, outlining, and constructive solid geometry rendering.
	
	The stencil test conditionally eliminates a pixel based on the outcome of a comparison between the reference value and the value in the stencil buffer. To enable and disable the test, call $(REF enable) and $(REF disable) with argument `STENCIL_TEST`. To specify actions based on the outcome of the stencil test, call $(REF stencilOp) or $(REF stencilOpSeparate).
	
	There can be two separate sets of $(I `func`), $(I `ref`), and $(I `mask`) parameters; one affects back-facing polygons, and the other affects front-facing polygons as well as other non-polygon primitives. $(REF stencilFunc) sets both front and back stencil state to the same values, as if $(REF stencilFuncSeparate) were called with $(I `face`) set to `FRONT_AND_BACK`.
	
	$(I `func`) is a symbolic constant that determines the stencil comparison function. It accepts one of eight values, shown in the following list. $(I `ref`) is an integer reference value that is used in the stencil comparison. It is clamped to the range [0, 2n - 1], where n is the number of bitplanes in the stencil buffer. $(I `mask`) is bitwise ANDed with both the reference value and the stored stencil value, with the ANDed values participating in the comparison.
	
	If $(I stencil) represents the value stored in the corresponding stencil buffer location, the following list shows the effect of each comparison function that can be specified by $(I `func`). Only if the comparison succeeds is the pixel passed through to the next stage in the rasterization process (see $(REF stencilOp)). All tests treat $(I stencil) values as unsigned integers in the range [0, 2n - 1], where n is the number of bitplanes in the stencil buffer.
	
	The following values are accepted by $(I `func`):
	
	- `NEVER`: Always fails.
	
	- `LESS`: Passes if ( $(I `ref`) & $(I `mask`) ) < ( $(I stencil) & $(I `mask`) ).
	
	- `LEQUAL`: Passes if ( $(I `ref`) & $(I `mask`) ) <= ( $(I stencil) & $(I `mask`) ).
	
	- `GREATER`: Passes if ( $(I `ref`) & $(I `mask`) ) > ( $(I stencil) & $(I `mask`) ).
	
	- `GEQUAL`: Passes if ( $(I `ref`) & $(I `mask`) ) >= ( $(I stencil) & $(I `mask`) ).
	
	- `EQUAL`: Passes if ( $(I `ref`) & $(I `mask`) ) = ( $(I stencil) & $(I `mask`) ).
	
	- `NOTEQUAL`: Passes if ( $(I `ref`) & $(I `mask`) ) != ( $(I stencil) & $(I `mask`) ).
	
	- `ALWAYS`: Always passes.
	
	Params:
	face = Specifies whether front and/or back stencil state is updated. Three symbolic constants are valid: `FRONT`, `BACK`, and `FRONT_AND_BACK`.
	func = Specifies the test function. Eight symbolic constants are valid: `NEVER`, `LESS`, `LEQUAL`, `GREATER`, `GEQUAL`, `EQUAL`, `NOTEQUAL`, and `ALWAYS`. The initial value is `ALWAYS`.
	ref = Specifies the reference value for the stencil test. $(I `ref`) is clamped to the range   0  2 n  - 1   , where n is the number of bitplanes in the stencil buffer. The initial value is 0.
	mask = Specifies a mask that is ANDed with both the reference value and the stored stencil value when the test is done. The initial value is all 1's.
	*/
	void stencilFuncSeparate(Enum face, Enum func, Int ref_, UInt mask);
	
	/**
	$(REF stencilMaskSeparate) controls the writing of individual bits in the stencil planes. The least significant n bits of $(I `mask`), where n is the number of bits in the stencil buffer, specify a mask. Where a 1 appears in the mask, it's possible to write to the corresponding bit in the stencil buffer. Where a 0 appears, the corresponding bit is write-protected. Initially, all bits are enabled for writing.
	
	There can be two separate $(I `mask`) writemasks; one affects back-facing polygons, and the other affects front-facing polygons as well as other non-polygon primitives. $(REF stencilMask) sets both front and back stencil writemasks to the same values, as if $(REF stencilMaskSeparate) were called with $(I `face`) set to `FRONT_AND_BACK`.
	
	Params:
	face = Specifies whether the front and/or back stencil writemask is updated. Three symbolic constants are valid: `FRONT`, `BACK`, and `FRONT_AND_BACK`.
	mask = Specifies a bit mask to enable and disable writing of individual bits in the stencil planes. Initially, the mask is all 1's.
	*/
	void stencilMaskSeparate(Enum face, UInt mask);
	
	/**
	In order to create a complete shader program, there must be a way to specify the list of things that will be linked together. Program objects provide this mechanism. Shaders that are to be linked together in a program object must first be attached to that program object. $(REF attachShader) attaches the shader object specified by $(I `shader`) to the program object specified by $(I `program`). This indicates that $(I `shader`) will be included in link operations that will be performed on $(I `program`).
	
	All operations that can be performed on a shader object are valid whether or not the shader object is attached to a program object. It is permissible to attach a shader object to a program object before source code has been loaded into the shader object or before the shader object has been compiled. It is permissible to attach multiple shader objects of the same type because each may contain a portion of the complete shader. It is also permissible to attach a shader object to more than one program object. If a shader object is deleted while it is attached to a program object, it will be flagged for deletion, and deletion will not occur until $(REF detachShader) is called to detach it from all program objects to which it is attached.
	
	Params:
	program = Specifies the program object to which a shader object will be attached.
	shader = Specifies the shader object that is to be attached.
	*/
	void attachShader(UInt program, UInt shader);
	
	/**
	$(REF bindAttribLocation) is used to associate a user-defined attribute variable in the program object specified by $(I `program`) with a generic vertex attribute index. The name of the user-defined attribute variable is passed as a null terminated string in $(I `name`). The generic vertex attribute index to be bound to this variable is specified by $(I `index`). When $(I `program`) is made part of current state, values provided via the generic vertex attribute $(I `index`) will modify the value of the user-defined attribute variable specified by $(I `name`).
	
	If $(I `name`) refers to a matrix attribute variable, $(I `index`) refers to the first column of the matrix. Other matrix columns are then automatically bound to locations $(I `index+1`) for a matrix of type `mat2`; $(I `index+1`) and $(I `index+2`) for a matrix of type `mat3`; and $(I `index+1`), $(I `index+2`), and $(I `index+3`) for a matrix of type `mat4`.
	
	This command makes it possible for vertex shaders to use descriptive names for attribute variables rather than generic variables that are numbered from zero to the value of `MAX_VERTEX_ATTRIBS` minus one. The values sent to each generic attribute index are part of current state. If a different program object is made current by calling $(REF useProgram), the generic vertex attributes are tracked in such a way that the same values will be observed by attributes in the new program object that are also bound to $(I `index`).
	
	Attribute variable name-to-generic attribute index bindings for a program object can be explicitly assigned at any time by calling $(REF bindAttribLocation). Attribute bindings do not go into effect until $(REF linkProgram) is called. After a program object has been linked successfully, the index values for generic attributes remain fixed (and their values can be queried) until the next link command occurs.
	
	Any attribute binding that occurs after the program object has been linked will not take effect until the next time the program object is linked.
	
	Params:
	program = Specifies the handle of the program object in which the association is to be made.
	index = Specifies the index of the generic vertex attribute to be bound.
	name = Specifies a null terminated string containing the name of the vertex shader attribute variable to which $(I `index`) is to be bound.
	*/
	void bindAttribLocation(UInt program, UInt index, const(Char)* name);
	
	/**
	$(REF compileShader) compiles the source code strings that have been stored in the shader object specified by $(I `shader`).
	
	The compilation status will be stored as part of the shader object's state. This value will be set to `TRUE` if the shader was compiled without errors and is ready for use, and `FALSE` otherwise. It can be queried by calling $(REF getShader) with arguments $(I `shader`) and `COMPILE_STATUS`.
	
	Compilation of a shader can fail for a number of reasons as specified by the OpenGL Shading Language Specification. Whether or not the compilation was successful, information about the compilation can be obtained from the shader object's information log by calling $(REF getShaderInfoLog).
	
	Params:
	shader = Specifies the shader object to be compiled.
	*/
	void compileShader(UInt shader);
	
	/**
	$(REF createProgram) creates an empty program object and returns a non-zero value by which it can be referenced. A program object is an object to which shader objects can be attached. This provides a mechanism to specify the shader objects that will be linked to create a program. It also provides a means for checking the compatibility of the shaders that will be used to create a program (for instance, checking the compatibility between a vertex shader and a fragment shader). When no longer needed as part of a program object, shader objects can be detached.
	
	One or more executables are created in a program object by successfully attaching shader objects to it with $(REF attachShader), successfully compiling the shader objects with $(REF compileShader), and successfully linking the program object with $(REF linkProgram). These executables are made part of current state when $(REF useProgram) is called. Program objects can be deleted by calling $(REF deleteProgram). The memory associated with the program object will be deleted when it is no longer part of current rendering state for any context.
	
	Params:
	*/
	uint createProgram();
	
	/**
	$(REF createShader) creates an empty shader object and returns a non-zero value by which it can be referenced. A shader object is used to maintain the source code strings that define a shader. $(I `shaderType`) indicates the type of shader to be created. Five types of shader are supported. A shader of type `COMPUTE_SHADER` is a shader that is intended to run on the programmable compute processor. A shader of type `VERTEX_SHADER` is a shader that is intended to run on the programmable vertex processor. A shader of type `TESS_CONTROL_SHADER` is a shader that is intended to run on the programmable tessellation processor in the control stage. A shader of type `TESS_EVALUATION_SHADER` is a shader that is intended to run on the programmable tessellation processor in the evaluation stage. A shader of type `GEOMETRY_SHADER` is a shader that is intended to run on the programmable geometry processor. A shader of type `FRAGMENT_SHADER` is a shader that is intended to run on the programmable fragment processor.
	
	When created, a shader object's `SHADER_TYPE` parameter is set to either `COMPUTE_SHADER`, `VERTEX_SHADER`, `TESS_CONTROL_SHADER`, `TESS_EVALUATION_SHADER`, `GEOMETRY_SHADER` or `FRAGMENT_SHADER`, depending on the value of $(I `shaderType`).
	
	Params:
	shaderType = Specifies the type of shader to be created. Must be one of `COMPUTE_SHADER`, `VERTEX_SHADER`, `TESS_CONTROL_SHADER`, `TESS_EVALUATION_SHADER`, `GEOMETRY_SHADER`, or `FRAGMENT_SHADER`.
	*/
	UInt createShader(Enum shaderType);
	
	/**
	$(REF deleteProgram) frees the memory and invalidates the name associated with the program object specified by $(I `program.`) This command effectively undoes the effects of a call to $(REF createProgram).
	
	If a program object is in use as part of current rendering state, it will be flagged for deletion, but it will not be deleted until it is no longer part of current state for any rendering context. If a program object to be deleted has shader objects attached to it, those shader objects will be automatically detached but not deleted unless they have already been flagged for deletion by a previous call to $(REF deleteShader). A value of 0 for $(I `program`) will be silently ignored.
	
	To determine whether a program object has been flagged for deletion, call $(REF getProgram) with arguments $(I `program`) and `DELETE_STATUS`.
	
	Params:
	program = Specifies the program object to be deleted.
	*/
	void deleteProgram(UInt program);
	
	/**
	$(REF deleteShader) frees the memory and invalidates the name associated with the shader object specified by $(I `shader`). This command effectively undoes the effects of a call to $(REF createShader).
	
	If a shader object to be deleted is attached to a program object, it will be flagged for deletion, but it will not be deleted until it is no longer attached to any program object, for any rendering context (i.e., it must be detached from wherever it was attached before it will be deleted). A value of 0 for $(I `shader`) will be silently ignored.
	
	To determine whether an object has been flagged for deletion, call $(REF getShader) with arguments $(I `shader`) and `DELETE_STATUS`.
	
	Params:
	shader = Specifies the shader object to be deleted.
	*/
	void deleteShader(UInt shader);
	
	/**
	$(REF detachShader) detaches the shader object specified by $(I `shader`) from the program object specified by $(I `program`). This command can be used to undo the effect of the command $(REF attachShader).
	
	If $(I `shader`) has already been flagged for deletion by a call to $(REF deleteShader) and it is not attached to any other program object, it will be deleted after it has been detached.
	
	Params:
	program = Specifies the program object from which to detach the shader object.
	shader = Specifies the shader object to be detached.
	*/
	void detachShader(UInt program, UInt shader);
	
	/**
	$(REF enableVertexAttribArray) and $(REF enableVertexArrayAttrib) enable the generic vertex attribute array specified by $(I `index`). $(REF enableVertexAttribArray) uses currently bound vertex array object for the operation, whereas $(REF enableVertexArrayAttrib) updates state of the vertex array object with ID $(I `vaobj`).
	
	$(REF disableVertexAttribArray) and $(REF disableVertexArrayAttrib) disable the generic vertex attribute array specified by $(I `index`). $(REF disableVertexAttribArray) uses currently bound vertex array object for the operation, whereas $(REF disableVertexArrayAttrib) updates state of the vertex array object with ID $(I `vaobj`).
	
	By default, all client-side capabilities are disabled, including all generic vertex attribute arrays. If enabled, the values in the generic vertex attribute array will be accessed and used for rendering when calls are made to vertex array commands such as $(REF drawArrays), $(REF drawElements), $(REF drawRangeElements), $(REF multiDrawElements), or $(REF multiDrawArrays).
	
	Params:
	index = Specifies the index of the generic vertex attribute to be enabled or disabled.
	*/
	void disableVertexAttribArray(UInt index);
	
	/**
	$(REF enableVertexAttribArray) and $(REF enableVertexArrayAttrib) enable the generic vertex attribute array specified by $(I `index`). $(REF enableVertexAttribArray) uses currently bound vertex array object for the operation, whereas $(REF enableVertexArrayAttrib) updates state of the vertex array object with ID $(I `vaobj`).
	
	$(REF disableVertexAttribArray) and $(REF disableVertexArrayAttrib) disable the generic vertex attribute array specified by $(I `index`). $(REF disableVertexAttribArray) uses currently bound vertex array object for the operation, whereas $(REF disableVertexArrayAttrib) updates state of the vertex array object with ID $(I `vaobj`).
	
	By default, all client-side capabilities are disabled, including all generic vertex attribute arrays. If enabled, the values in the generic vertex attribute array will be accessed and used for rendering when calls are made to vertex array commands such as $(REF drawArrays), $(REF drawElements), $(REF drawRangeElements), $(REF multiDrawElements), or $(REF multiDrawArrays).
	
	Params:
	index = Specifies the index of the generic vertex attribute to be enabled or disabled.
	*/
	void enableVertexAttribArray(UInt index);
	
	/**
	$(REF getActiveAttrib) returns information about an active attribute variable in the program object specified by $(I `program`). The number of active attributes can be obtained by calling $(REF getProgram) with the value `ACTIVE_ATTRIBUTES`. A value of 0 for $(I `index`) selects the first active attribute variable. Permissible values for $(I `index`) range from zero to the number of active attribute variables minus one.
	
	A vertex shader may use either built-in attribute variables, user-defined attribute variables, or both. Built-in attribute variables have a prefix of "gl_" and reference conventional OpenGL vertex attribtes (e.g., $(I `gl_Vertex`), $(I `gl_Normal`), etc., see the OpenGL Shading Language specification for a complete list.) User-defined attribute variables have arbitrary names and obtain their values through numbered generic vertex attributes. An attribute variable (either built-in or user-defined) is considered active if it is determined during the link operation that it may be accessed during program execution. Therefore, $(I `program`) should have previously been the target of a call to $(REF linkProgram), but it is not necessary for it to have been linked successfully.
	
	The size of the character buffer required to store the longest attribute variable name in $(I `program`) can be obtained by calling $(REF getProgram) with the value `ACTIVE_ATTRIBUTE_MAX_LENGTH`. This value should be used to allocate a buffer of sufficient size to store the returned attribute name. The size of this character buffer is passed in $(I `bufSize`), and a pointer to this character buffer is passed in $(I `name`).
	
	$(REF getActiveAttrib) returns the name of the attribute variable indicated by $(I `index`), storing it in the character buffer specified by $(I `name`). The string returned will be null terminated. The actual number of characters written into this buffer is returned in $(I `length`), and this count does not include the null termination character. If the length of the returned string is not required, a value of `NULL` can be passed in the $(I `length`) argument.
	
	The $(I `type`) argument specifies a pointer to a variable into which the attribute variable's data type will be written. The symbolic constants `FLOAT`, `FLOAT_VEC2`, `FLOAT_VEC3`, `FLOAT_VEC4`, `FLOAT_MAT2`, `FLOAT_MAT3`, `FLOAT_MAT4`, `FLOAT_MAT2x3`, `FLOAT_MAT2x4`, `FLOAT_MAT3x2`, `FLOAT_MAT3x4`, `FLOAT_MAT4x2`, `FLOAT_MAT4x3`, `INT`, `INT_VEC2`, `INT_VEC3`, `INT_VEC4`, `UNSIGNED_INT`, `UNSIGNED_INT_VEC2`, `UNSIGNED_INT_VEC3`, `UNSIGNED_INT_VEC4`, `DOUBLE`, `DOUBLE_VEC2`, `DOUBLE_VEC3`, `DOUBLE_VEC4`, `DOUBLE_MAT2`, `DOUBLE_MAT3`, `DOUBLE_MAT4`, `DOUBLE_MAT2x3`, `DOUBLE_MAT2x4`, `DOUBLE_MAT3x2`, `DOUBLE_MAT3x4`, `DOUBLE_MAT4x2`, or `DOUBLE_MAT4x3` may be returned. The $(I `size`) argument will return the size of the attribute, in units of the type returned in $(I `type`).
	
	The list of active attribute variables may include both built-in attribute variables (which begin with the prefix "gl_") as well as user-defined attribute variable names.
	
	This function will return as much information as it can about the specified active attribute variable. If no information is available, $(I `length`) will be 0, and $(I `name`) will be an empty string. This situation could occur if this function is called after a link operation that failed. If an error occurs, the return values $(I `length`), $(I `size`), $(I `type`), and $(I `name`) will be unmodified.
	
	Params:
	program = Specifies the program object to be queried.
	index = Specifies the index of the attribute variable to be queried.
	bufSize = Specifies the maximum number of characters OpenGL is allowed to write in the character buffer indicated by $(I `name`).
	length = Returns the number of characters actually written by OpenGL in the string indicated by $(I `name`) (excluding the null terminator) if a value other than `NULL` is passed.
	size = Returns the size of the attribute variable.
	type = Returns the data type of the attribute variable.
	name = Returns a null terminated string containing the name of the attribute variable.
	*/
	void getActiveAttrib(UInt program, UInt index, Sizei bufSize, Sizei* length, Int* size, Enum* type, Char* name);
	
	/**
	$(REF getActiveUniform) returns information about an active uniform variable in the program object specified by $(I `program`). The number of active uniform variables can be obtained by calling $(REF getProgram) with the value `ACTIVE_UNIFORMS`. A value of 0 for $(I `index`) selects the first active uniform variable. Permissible values for $(I `index`) range from zero to the number of active uniform variables minus one.
	
	Shaders may use either built-in uniform variables, user-defined uniform variables, or both. Built-in uniform variables have a prefix of "gl_" and reference existing OpenGL state or values derived from such state (e.g., $(I `gl_DepthRangeParameters`), see the OpenGL Shading Language specification for a complete list.) User-defined uniform variables have arbitrary names and obtain their values from the application through calls to $(REF uniform). A uniform variable (either built-in or user-defined) is considered active if it is determined during the link operation that it may be accessed during program execution. Therefore, $(I `program`) should have previously been the target of a call to $(REF linkProgram), but it is not necessary for it to have been linked successfully.
	
	The size of the character buffer required to store the longest uniform variable name in $(I `program`) can be obtained by calling $(REF getProgram) with the value `ACTIVE_UNIFORM_MAX_LENGTH`. This value should be used to allocate a buffer of sufficient size to store the returned uniform variable name. The size of this character buffer is passed in $(I `bufSize`), and a pointer to this character buffer is passed in $(I `name.`)
	
	$(REF getActiveUniform) returns the name of the uniform variable indicated by $(I `index`), storing it in the character buffer specified by $(I `name`). The string returned will be null terminated. The actual number of characters written into this buffer is returned in $(I `length`), and this count does not include the null termination character. If the length of the returned string is not required, a value of `NULL` can be passed in the $(I `length`) argument.
	
	The $(I `type`) argument will return a pointer to the uniform variable's data type. The symbolic constants returned for uniform types are shown in the table below.
	
	If one or more elements of an array are active, the name of the array is returned in $(I `name`), the type is returned in $(I `type`), and the $(I `size`) parameter returns the highest array element index used, plus one, as determined by the compiler and/or linker. Only one active uniform variable will be reported for a uniform array.
	
	Uniform variables that are declared as structures or arrays of structures will not be returned directly by this function. Instead, each of these uniform variables will be reduced to its fundamental components containing the "." and "[]" operators such that each of the names is valid as an argument to $(REF getUniformLocation). Each of these reduced uniform variables is counted as one active uniform variable and is assigned an index. A valid name cannot be a structure, an array of structures, or a subcomponent of a vector or matrix.
	
	The size of the uniform variable will be returned in $(I `size`). Uniform variables other than arrays will have a size of 1. Structures and arrays of structures will be reduced as described earlier, such that each of the names returned will be a data type in the earlier list. If this reduction results in an array, the size returned will be as described for uniform arrays; otherwise, the size returned will be 1.
	
	The list of active uniform variables may include both built-in uniform variables (which begin with the prefix "gl_") as well as user-defined uniform variable names.
	
	This function will return as much information as it can about the specified active uniform variable. If no information is available, $(I `length`) will be 0, and $(I `name`) will be an empty string. This situation could occur if this function is called after a link operation that failed. If an error occurs, the return values $(I `length`), $(I `size`), $(I `type`), and $(I `name`) will be unmodified.
	
	Params:
	program = Specifies the program object to be queried.
	index = Specifies the index of the uniform variable to be queried.
	bufSize = Specifies the maximum number of characters OpenGL is allowed to write in the character buffer indicated by $(I `name`).
	length = Returns the number of characters actually written by OpenGL in the string indicated by $(I `name`) (excluding the null terminator) if a value other than `NULL` is passed.
	size = Returns the size of the uniform variable.
	type = Returns the data type of the uniform variable.
	name = Returns a null terminated string containing the name of the uniform variable.
	*/
	void getActiveUniform(UInt program, UInt index, Sizei bufSize, Sizei* length, Int* size, Enum* type, Char* name);
	
	/**
	$(REF getAttachedShaders) returns the names of the shader objects attached to $(I `program`). The names of shader objects that are attached to $(I `program`) will be returned in $(I `shaders.`) The actual number of shader names written into $(I `shaders`) is returned in $(I `count.`) If no shader objects are attached to $(I `program`), $(I `count`) is set to 0. The maximum number of shader names that may be returned in $(I `shaders`) is specified by $(I `maxCount`).
	
	If the number of names actually returned is not required (for instance, if it has just been obtained by calling $(REF getProgram)), a value of `NULL` may be passed for count. If no shader objects are attached to $(I `program`), a value of 0 will be returned in $(I `count`). The actual number of attached shaders can be obtained by calling $(REF getProgram) with the value `ATTACHED_SHADERS`.
	
	Params:
	program = Specifies the program object to be queried.
	maxCount = Specifies the size of the array for storing the returned object names.
	count = Returns the number of names actually returned in $(I `shaders`).
	shaders = Specifies an array that is used to return the names of attached shader objects.
	*/
	void getAttachedShaders(UInt program, Sizei maxCount, Sizei* count, UInt* shaders);
	
	/**
	$(REF getAttribLocation) queries the previously linked program object specified by $(I `program`) for the attribute variable specified by $(I `name`) and returns the index of the generic vertex attribute that is bound to that attribute variable. If $(I `name`) is a matrix attribute variable, the index of the first column of the matrix is returned. If the named attribute variable is not an active attribute in the specified program object or if $(I `name`) starts with the reserved prefix "gl_", a value of -1 is returned.
	
	The association between an attribute variable name and a generic attribute index can be specified at any time by calling $(REF bindAttribLocation). Attribute bindings do not go into effect until $(REF linkProgram) is called. After a program object has been linked successfully, the index values for attribute variables remain fixed until the next link command occurs. The attribute values can only be queried after a link if the link was successful. $(REF getAttribLocation) returns the binding that actually went into effect the last time $(REF linkProgram) was called for the specified program object. Attribute bindings that have been specified since the last link operation are not returned by $(REF getAttribLocation).
	
	Params:
	program = Specifies the program object to be queried.
	name = Points to a null terminated string containing the name of the attribute variable whose location is to be queried.
	*/
	Int getAttribLocation(UInt program, const(Char)* name);
	
	/**
	$(REF getProgram) returns in $(I `params`) the value of a parameter for a specific program object. The following parameters are defined:
	
	- `DELETE_STATUS`: $(I `params`) returns `TRUE` if $(I `program`) is currently flagged for deletion, and `FALSE` otherwise.
	
	- `LINK_STATUS`: $(I `params`) returns `TRUE` if the last link operation on $(I `program`) was successful, and `FALSE` otherwise.
	
	- `VALIDATE_STATUS`: $(I `params`) returns `TRUE` or if the last validation operation on $(I `program`) was successful, and `FALSE` otherwise.
	
	- `INFO_LOG_LENGTH`: $(I `params`) returns the number of characters in the information log for $(I `program`) including the null termination character (i.e., the size of the character buffer required to store the information log). If $(I `program`) has no information log, a value of 0 is returned.
	
	- `ATTACHED_SHADERS`: $(I `params`) returns the number of shader objects attached to $(I `program`).
	
	- `ACTIVE_ATOMIC_COUNTER_BUFFERS`: $(I `params`) returns the number of active attribute atomic counter buffers used by $(I `program`).
	
	- `ACTIVE_ATTRIBUTES`: $(I `params`) returns the number of active attribute variables for $(I `program`).
	
	- `ACTIVE_ATTRIBUTE_MAX_LENGTH`: $(I `params`) returns the length of the longest active attribute name for $(I `program`), including the null termination character (i.e., the size of the character buffer required to store the longest attribute name). If no active attributes exist, 0 is returned.
	
	- `ACTIVE_UNIFORMS`: $(I `params`) returns the number of active uniform variables for $(I `program`).
	
	- `ACTIVE_UNIFORM_MAX_LENGTH`: $(I `params`) returns the length of the longest active uniform variable name for $(I `program`), including the null termination character (i.e., the size of the character buffer required to store the longest uniform variable name). If no active uniform variables exist, 0 is returned.
	
	- `PROGRAM_BINARY_LENGTH`: $(I `params`) returns the length of the program binary, in bytes that will be returned by a call to $(REF getProgramBinary). When a progam's `LINK_STATUS` is `FALSE`, its program binary length is zero.
	
	- `COMPUTE_WORK_GROUP_SIZE`: $(I `params`) returns an array of three integers containing the local work group size of the compute program as specified by its input layout qualifier(s). $(I `program`) must be the name of a program object that has been previously linked successfully and contains a binary for the compute shader stage.
	
	- `TRANSFORM_FEEDBACK_BUFFER_MODE`: $(I `params`) returns a symbolic constant indicating the buffer mode used when transform feedback is active. This may be `SEPARATE_ATTRIBS` or `INTERLEAVED_ATTRIBS`.
	
	- `TRANSFORM_FEEDBACK_VARYINGS`: $(I `params`) returns the number of varying variables to capture in transform feedback mode for the program.
	
	- `TRANSFORM_FEEDBACK_VARYING_MAX_LENGTH`: $(I `params`) returns the length of the longest variable name to be used for transform feedback, including the null-terminator.
	
	- `GEOMETRY_VERTICES_OUT`: $(I `params`) returns the maximum number of vertices that the geometry shader in $(I `program`) will output.
	
	- `GEOMETRY_INPUT_TYPE`: $(I `params`) returns a symbolic constant indicating the primitive type accepted as input to the geometry shader contained in $(I `program`).
	
	- `GEOMETRY_OUTPUT_TYPE`: $(I `params`) returns a symbolic constant indicating the primitive type that will be output by the geometry shader contained in $(I `program`).
	
	Params:
	program = Specifies the program object to be queried.
	pname = Specifies the object parameter. Accepted symbolic names are `DELETE_STATUS`, `LINK_STATUS`, `VALIDATE_STATUS`, `INFO_LOG_LENGTH`, `ATTACHED_SHADERS`, `ACTIVE_ATOMIC_COUNTER_BUFFERS`, `ACTIVE_ATTRIBUTES`, `ACTIVE_ATTRIBUTE_MAX_LENGTH`, `ACTIVE_UNIFORMS`, `ACTIVE_UNIFORM_BLOCKS`, `ACTIVE_UNIFORM_BLOCK_MAX_NAME_LENGTH`, `ACTIVE_UNIFORM_MAX_LENGTH`, `COMPUTE_WORK_GROUP_SIZE` `PROGRAM_BINARY_LENGTH`, `TRANSFORM_FEEDBACK_BUFFER_MODE`, `TRANSFORM_FEEDBACK_VARYINGS`, `TRANSFORM_FEEDBACK_VARYING_MAX_LENGTH`, `GEOMETRY_VERTICES_OUT`, `GEOMETRY_INPUT_TYPE`, and `GEOMETRY_OUTPUT_TYPE`.
	params = Returns the requested object parameter.
	*/
	void getProgramiv(UInt program, Enum pname, Int* params);
	
	/**
	$(REF getProgramInfoLog) returns the information log for the specified program object. The information log for a program object is modified when the program object is linked or validated. The string that is returned will be null terminated.
	
	$(REF getProgramInfoLog) returns in $(I `infoLog`) as much of the information log as it can, up to a maximum of $(I `maxLength`) characters. The number of characters actually returned, excluding the null termination character, is specified by $(I `length`). If the length of the returned string is not required, a value of `NULL` can be passed in the $(I `length`) argument. The size of the buffer required to store the returned information log can be obtained by calling $(REF getProgram) with the value `INFO_LOG_LENGTH`.
	
	The information log for a program object is either an empty string, or a string containing information about the last link operation, or a string containing information about the last validation operation. It may contain diagnostic messages, warning messages, and other information. When a program object is created, its information log will be a string of length 0.
	
	Params:
	program = Specifies the program object whose information log is to be queried.
	maxLength = Specifies the size of the character buffer for storing the returned information log.
	length = Returns the length of the string returned in $(I `infoLog`) (excluding the null terminator).
	infoLog = Specifies an array of characters that is used to return the information log.
	*/
	void getProgramInfoLog(UInt program, Sizei maxLength, Sizei* length, Char* infoLog);
	
	/**
	$(REF getShader) returns in $(I `params`) the value of a parameter for a specific shader object. The following parameters are defined:
	
	- `SHADER_TYPE`: $(I `params`) returns `VERTEX_SHADER` if $(I `shader`) is a vertex shader object, `GEOMETRY_SHADER` if $(I `shader`) is a geometry shader object, and `FRAGMENT_SHADER` if $(I `shader`) is a fragment shader object.
	
	- `DELETE_STATUS`: $(I `params`) returns `TRUE` if $(I `shader`) is currently flagged for deletion, and `FALSE` otherwise.
	
	- `COMPILE_STATUS`: $(I `params`) returns `TRUE` if the last compile operation on $(I `shader`) was successful, and `FALSE` otherwise.
	
	- `INFO_LOG_LENGTH`: $(I `params`) returns the number of characters in the information log for $(I `shader`) including the null termination character (i.e., the size of the character buffer required to store the information log). If $(I `shader`) has no information log, a value of 0 is returned.
	
	- `SHADER_SOURCE_LENGTH`: $(I `params`) returns the length of the concatenation of the source strings that make up the shader source for the $(I `shader`), including the null termination character. (i.e., the size of the character buffer required to store the shader source). If no source code exists, 0 is returned.
	
	Params:
	shader = Specifies the shader object to be queried.
	pname = Specifies the object parameter. Accepted symbolic names are `SHADER_TYPE`, `DELETE_STATUS`, `COMPILE_STATUS`, `INFO_LOG_LENGTH`, `SHADER_SOURCE_LENGTH`.
	params = Returns the requested object parameter.
	*/
	void getShaderiv(UInt shader, Enum pname, Int* params);
	
	/**
	$(REF getShaderInfoLog) returns the information log for the specified shader object. The information log for a shader object is modified when the shader is compiled. The string that is returned will be null terminated.
	
	$(REF getShaderInfoLog) returns in $(I `infoLog`) as much of the information log as it can, up to a maximum of $(I `maxLength`) characters. The number of characters actually returned, excluding the null termination character, is specified by $(I `length`). If the length of the returned string is not required, a value of `NULL` can be passed in the $(I `length`) argument. The size of the buffer required to store the returned information log can be obtained by calling $(REF getShader) with the value `INFO_LOG_LENGTH`.
	
	The information log for a shader object is a string that may contain diagnostic messages, warning messages, and other information about the last compile operation. When a shader object is created, its information log will be a string of length 0.
	
	Params:
	shader = Specifies the shader object whose information log is to be queried.
	maxLength = Specifies the size of the character buffer for storing the returned information log.
	length = Returns the length of the string returned in $(I `infoLog`) (excluding the null terminator).
	infoLog = Specifies an array of characters that is used to return the information log.
	*/
	void getShaderInfoLog(UInt shader, Sizei maxLength, Sizei* length, Char* infoLog);
	
	/**
	$(REF getShaderSource) returns the concatenation of the source code strings from the shader object specified by $(I `shader`). The source code strings for a shader object are the result of a previous call to $(REF shaderSource). The string returned by the function will be null terminated.
	
	$(REF getShaderSource) returns in $(I `source`) as much of the source code string as it can, up to a maximum of $(I `bufSize`) characters. The number of characters actually returned, excluding the null termination character, is specified by $(I `length`). If the length of the returned string is not required, a value of `NULL` can be passed in the $(I `length`) argument. The size of the buffer required to store the returned source code string can be obtained by calling $(REF getShader) with the value `SHADER_SOURCE_LENGTH`.
	
	Params:
	shader = Specifies the shader object to be queried.
	bufSize = Specifies the size of the character buffer for storing the returned source code string.
	length = Returns the length of the string returned in $(I `source`) (excluding the null terminator).
	source = Specifies an array of characters that is used to return the source code string.
	*/
	void getShaderSource(UInt shader, Sizei bufSize, Sizei* length, Char* source);
	
	/**
	$(REF getUniformLocation ) returns an integer that represents the location of a specific uniform variable within a program object. $(I `name`) must be a null terminated string that contains no white space. $(I `name`) must be an active uniform variable name in $(I `program`) that is not a structure, an array of structures, or a subcomponent of a vector or a matrix. This function returns -1 if $(I `name`) does not correspond to an active uniform variable in $(I `program`), if $(I `name`) starts with the reserved prefix "gl_", or if $(I `name`) is associated with an atomic counter or a named uniform block.
	
	Uniform variables that are structures or arrays of structures may be queried by calling $(REF getUniformLocation) for each field within the structure. The array element operator "[]" and the structure field operator "." may be used in $(I `name`) in order to select elements within an array or fields within a structure. The result of using these operators is not allowed to be another structure, an array of structures, or a subcomponent of a vector or a matrix. Except if the last part of $(I `name`) indicates a uniform variable array, the location of the first element of an array can be retrieved by using the name of the array, or by using the name appended by "[0]".
	
	The actual locations assigned to uniform variables are not known until the program object is linked successfully. After linking has occurred, the command $(REF getUniformLocation) can be used to obtain the location of a uniform variable. This location value can then be passed to $(REF uniform) to set the value of the uniform variable or to $(REF getUniform) in order to query the current value of the uniform variable. After a program object has been linked successfully, the index values for uniform variables remain fixed until the next link command occurs. Uniform variable locations and values can only be queried after a link if the link was successful.
	
	Params:
	program = Specifies the program object to be queried.
	name = Points to a null terminated string containing the name of the uniform variable whose location is to be queried.
	*/
	Int getUniformLocation(UInt program, const(Char)* name);
	
	/**
	$(REF getUniform) and $(REF getnUniform) return in $(I `params`) the value(s) of the specified uniform variable. The type of the uniform variable specified by $(I `location`) determines the number of values returned. If the uniform variable is defined in the shader as a boolean, int, or float, a single value will be returned. If it is defined as a vec2, ivec2, or bvec2, two values will be returned. If it is defined as a vec3, ivec3, or bvec3, three values will be returned, and so on. To query values stored in uniform variables declared as arrays, call $(REF getUniform) for each element of the array. To query values stored in uniform variables declared as structures, call $(REF getUniform) for each field in the structure. The values for uniform variables declared as a matrix will be returned in column major order.
	
	The locations assigned to uniform variables are not known until the program object is linked. After linking has occurred, the command $(REF getUniformLocation) can be used to obtain the location of a uniform variable. This location value can then be passed to $(REF getUniform) or $(REF getnUniform) in order to query the current value of the uniform variable. After a program object has been linked successfully, the index values for uniform variables remain fixed until the next link command occurs. The uniform variable values can only be queried after a link if the link was successful.
	
	The only difference between $(REF getUniform) and $(REF getnUniform) is that $(REF getnUniform) will generate an error if size of the $(I `params`) buffer,as described by $(I `bufSize`), is not large enough to hold the result data.
	
	Params:
	program = Specifies the program object to be queried.
	location = Specifies the location of the uniform variable to be queried.
	params = Returns the value of the specified uniform variable.
	*/
	void getUniformfv(UInt program, Int location, Float* params);
	
	/**
	$(REF getUniform) and $(REF getnUniform) return in $(I `params`) the value(s) of the specified uniform variable. The type of the uniform variable specified by $(I `location`) determines the number of values returned. If the uniform variable is defined in the shader as a boolean, int, or float, a single value will be returned. If it is defined as a vec2, ivec2, or bvec2, two values will be returned. If it is defined as a vec3, ivec3, or bvec3, three values will be returned, and so on. To query values stored in uniform variables declared as arrays, call $(REF getUniform) for each element of the array. To query values stored in uniform variables declared as structures, call $(REF getUniform) for each field in the structure. The values for uniform variables declared as a matrix will be returned in column major order.
	
	The locations assigned to uniform variables are not known until the program object is linked. After linking has occurred, the command $(REF getUniformLocation) can be used to obtain the location of a uniform variable. This location value can then be passed to $(REF getUniform) or $(REF getnUniform) in order to query the current value of the uniform variable. After a program object has been linked successfully, the index values for uniform variables remain fixed until the next link command occurs. The uniform variable values can only be queried after a link if the link was successful.
	
	The only difference between $(REF getUniform) and $(REF getnUniform) is that $(REF getnUniform) will generate an error if size of the $(I `params`) buffer,as described by $(I `bufSize`), is not large enough to hold the result data.
	
	Params:
	program = Specifies the program object to be queried.
	location = Specifies the location of the uniform variable to be queried.
	params = Returns the value of the specified uniform variable.
	*/
	void getUniformiv(UInt program, Int location, Int* params);
	
	/**
	$(REF getVertexAttrib) returns in $(I `params`) the value of a generic vertex attribute parameter. The generic vertex attribute to be queried is specified by $(I `index`), and the parameter to be queried is specified by $(I `pname`).
	
	The accepted parameter names are as follows:
	
	- `VERTEX_ATTRIB_ARRAY_BUFFER_BINDING`: $(I `params`) returns a single value, the name of the buffer object currently bound to the binding point corresponding to generic vertex attribute array $(I `index`). If no buffer object is bound, 0 is returned. The initial value is 0.
	
	- `VERTEX_ATTRIB_ARRAY_ENABLED`: $(I `params`) returns a single value that is non-zero (true) if the vertex attribute array for $(I `index`) is enabled and 0 (false) if it is disabled. The initial value is `FALSE`.
	
	- `VERTEX_ATTRIB_ARRAY_SIZE`: $(I `params`) returns a single value, the size of the vertex attribute array for $(I `index`). The size is the number of values for each element of the vertex attribute array, and it will be 1, 2, 3, or 4. The initial value is 4.
	
	- `VERTEX_ATTRIB_ARRAY_STRIDE`: $(I `params`) returns a single value, the array stride for (number of bytes between successive elements in) the vertex attribute array for $(I `index`). A value of 0 indicates that the array elements are stored sequentially in memory. The initial value is 0.
	
	- `VERTEX_ATTRIB_ARRAY_TYPE`: $(I `params`) returns a single value, a symbolic constant indicating the array type for the vertex attribute array for $(I `index`). Possible values are `BYTE`, `UNSIGNED_BYTE`, `SHORT`, `UNSIGNED_SHORT`, `INT`, `UNSIGNED_INT`, `FLOAT`, and `DOUBLE`. The initial value is `FLOAT`.
	
	- `VERTEX_ATTRIB_ARRAY_NORMALIZED`: $(I `params`) returns a single value that is non-zero (true) if fixed-point data types for the vertex attribute array indicated by $(I `index`) are normalized when they are converted to floating point, and 0 (false) otherwise. The initial value is `FALSE`.
	
	- `VERTEX_ATTRIB_ARRAY_INTEGER`: $(I `params`) returns a single value that is non-zero (true) if fixed-point data types for the vertex attribute array indicated by $(I `index`) have integer data types, and 0 (false) otherwise. The initial value is 0 (`FALSE`).
	
	- `VERTEX_ATTRIB_ARRAY_LONG`: $(I `param`) returns a single value that is non-zero (true) if a vertex attribute is stored as an unconverted double, and 0 (false) otherwise. The initial value is 0 (`FALSE`).
	
	- `VERTEX_ATTRIB_ARRAY_DIVISOR`: $(I `params`) returns a single value that is the frequency divisor used for instanced rendering. See $(REF vertexAttribDivisor). The initial value is 0.
	
	- `VERTEX_ATTRIB_BINDING`: $(I `params`) returns a single value, the vertex buffer binding of the vertex attribute array $(I `index`).
	
	- `VERTEX_ATTRIB_RELATIVE_OFFSET`: $(I `params`) returns a single value that is the byte offset of the first element relative to the start of the vertex buffer binding specified attribute fetches from. The initial value is 0.
	
	- `CURRENT_VERTEX_ATTRIB`: $(I `params`) returns four values that represent the current value for the generic vertex attribute specified by index. Generic vertex attribute 0 is unique in that it has no current state, so an error will be generated if $(I `index`) is 0. The initial value for all other generic vertex attributes is (0,0,0,1).  $(REF getVertexAttribdv) and $(REF getVertexAttribfv) return the current attribute values as four single-precision floating-point values; $(REF getVertexAttribiv) reads them as floating-point values and converts them to four integer values; $(REF getVertexAttribIiv) and $(REF getVertexAttribIuiv) read and return them as signed or unsigned integer values, respectively; $(REF getVertexAttribLdv) reads and returns them as four double-precision floating-point values.
	
	All of the parameters except `CURRENT_VERTEX_ATTRIB` represent state stored in the currently bound vertex array object.
	
	Params:
	index = Specifies the generic vertex attribute parameter to be queried.
	pname = Specifies the symbolic name of the vertex attribute parameter to be queried. Accepted values are `VERTEX_ATTRIB_ARRAY_BUFFER_BINDING`, `VERTEX_ATTRIB_ARRAY_ENABLED`, `VERTEX_ATTRIB_ARRAY_SIZE`, `VERTEX_ATTRIB_ARRAY_STRIDE`, `VERTEX_ATTRIB_ARRAY_TYPE`, `VERTEX_ATTRIB_ARRAY_NORMALIZED`, `VERTEX_ATTRIB_ARRAY_INTEGER`, `VERTEX_ATTRIB_ARRAY_LONG`, `VERTEX_ATTRIB_ARRAY_DIVISOR`, `VERTEX_ATTRIB_BINDING`, `VERTEX_ATTRIB_RELATIVE_OFFSET` or `CURRENT_VERTEX_ATTRIB`.
	params = Returns the requested data.
	*/
	void getVertexAttribdv(UInt index, Enum pname, Double* params);
	
	/**
	$(REF getVertexAttrib) returns in $(I `params`) the value of a generic vertex attribute parameter. The generic vertex attribute to be queried is specified by $(I `index`), and the parameter to be queried is specified by $(I `pname`).
	
	The accepted parameter names are as follows:
	
	- `VERTEX_ATTRIB_ARRAY_BUFFER_BINDING`: $(I `params`) returns a single value, the name of the buffer object currently bound to the binding point corresponding to generic vertex attribute array $(I `index`). If no buffer object is bound, 0 is returned. The initial value is 0.
	
	- `VERTEX_ATTRIB_ARRAY_ENABLED`: $(I `params`) returns a single value that is non-zero (true) if the vertex attribute array for $(I `index`) is enabled and 0 (false) if it is disabled. The initial value is `FALSE`.
	
	- `VERTEX_ATTRIB_ARRAY_SIZE`: $(I `params`) returns a single value, the size of the vertex attribute array for $(I `index`). The size is the number of values for each element of the vertex attribute array, and it will be 1, 2, 3, or 4. The initial value is 4.
	
	- `VERTEX_ATTRIB_ARRAY_STRIDE`: $(I `params`) returns a single value, the array stride for (number of bytes between successive elements in) the vertex attribute array for $(I `index`). A value of 0 indicates that the array elements are stored sequentially in memory. The initial value is 0.
	
	- `VERTEX_ATTRIB_ARRAY_TYPE`: $(I `params`) returns a single value, a symbolic constant indicating the array type for the vertex attribute array for $(I `index`). Possible values are `BYTE`, `UNSIGNED_BYTE`, `SHORT`, `UNSIGNED_SHORT`, `INT`, `UNSIGNED_INT`, `FLOAT`, and `DOUBLE`. The initial value is `FLOAT`.
	
	- `VERTEX_ATTRIB_ARRAY_NORMALIZED`: $(I `params`) returns a single value that is non-zero (true) if fixed-point data types for the vertex attribute array indicated by $(I `index`) are normalized when they are converted to floating point, and 0 (false) otherwise. The initial value is `FALSE`.
	
	- `VERTEX_ATTRIB_ARRAY_INTEGER`: $(I `params`) returns a single value that is non-zero (true) if fixed-point data types for the vertex attribute array indicated by $(I `index`) have integer data types, and 0 (false) otherwise. The initial value is 0 (`FALSE`).
	
	- `VERTEX_ATTRIB_ARRAY_LONG`: $(I `param`) returns a single value that is non-zero (true) if a vertex attribute is stored as an unconverted double, and 0 (false) otherwise. The initial value is 0 (`FALSE`).
	
	- `VERTEX_ATTRIB_ARRAY_DIVISOR`: $(I `params`) returns a single value that is the frequency divisor used for instanced rendering. See $(REF vertexAttribDivisor). The initial value is 0.
	
	- `VERTEX_ATTRIB_BINDING`: $(I `params`) returns a single value, the vertex buffer binding of the vertex attribute array $(I `index`).
	
	- `VERTEX_ATTRIB_RELATIVE_OFFSET`: $(I `params`) returns a single value that is the byte offset of the first element relative to the start of the vertex buffer binding specified attribute fetches from. The initial value is 0.
	
	- `CURRENT_VERTEX_ATTRIB`: $(I `params`) returns four values that represent the current value for the generic vertex attribute specified by index. Generic vertex attribute 0 is unique in that it has no current state, so an error will be generated if $(I `index`) is 0. The initial value for all other generic vertex attributes is (0,0,0,1).  $(REF getVertexAttribdv) and $(REF getVertexAttribfv) return the current attribute values as four single-precision floating-point values; $(REF getVertexAttribiv) reads them as floating-point values and converts them to four integer values; $(REF getVertexAttribIiv) and $(REF getVertexAttribIuiv) read and return them as signed or unsigned integer values, respectively; $(REF getVertexAttribLdv) reads and returns them as four double-precision floating-point values.
	
	All of the parameters except `CURRENT_VERTEX_ATTRIB` represent state stored in the currently bound vertex array object.
	
	Params:
	index = Specifies the generic vertex attribute parameter to be queried.
	pname = Specifies the symbolic name of the vertex attribute parameter to be queried. Accepted values are `VERTEX_ATTRIB_ARRAY_BUFFER_BINDING`, `VERTEX_ATTRIB_ARRAY_ENABLED`, `VERTEX_ATTRIB_ARRAY_SIZE`, `VERTEX_ATTRIB_ARRAY_STRIDE`, `VERTEX_ATTRIB_ARRAY_TYPE`, `VERTEX_ATTRIB_ARRAY_NORMALIZED`, `VERTEX_ATTRIB_ARRAY_INTEGER`, `VERTEX_ATTRIB_ARRAY_LONG`, `VERTEX_ATTRIB_ARRAY_DIVISOR`, `VERTEX_ATTRIB_BINDING`, `VERTEX_ATTRIB_RELATIVE_OFFSET` or `CURRENT_VERTEX_ATTRIB`.
	params = Returns the requested data.
	*/
	void getVertexAttribfv(UInt index, Enum pname, Float* params);
	
	/**
	$(REF getVertexAttrib) returns in $(I `params`) the value of a generic vertex attribute parameter. The generic vertex attribute to be queried is specified by $(I `index`), and the parameter to be queried is specified by $(I `pname`).
	
	The accepted parameter names are as follows:
	
	- `VERTEX_ATTRIB_ARRAY_BUFFER_BINDING`: $(I `params`) returns a single value, the name of the buffer object currently bound to the binding point corresponding to generic vertex attribute array $(I `index`). If no buffer object is bound, 0 is returned. The initial value is 0.
	
	- `VERTEX_ATTRIB_ARRAY_ENABLED`: $(I `params`) returns a single value that is non-zero (true) if the vertex attribute array for $(I `index`) is enabled and 0 (false) if it is disabled. The initial value is `FALSE`.
	
	- `VERTEX_ATTRIB_ARRAY_SIZE`: $(I `params`) returns a single value, the size of the vertex attribute array for $(I `index`). The size is the number of values for each element of the vertex attribute array, and it will be 1, 2, 3, or 4. The initial value is 4.
	
	- `VERTEX_ATTRIB_ARRAY_STRIDE`: $(I `params`) returns a single value, the array stride for (number of bytes between successive elements in) the vertex attribute array for $(I `index`). A value of 0 indicates that the array elements are stored sequentially in memory. The initial value is 0.
	
	- `VERTEX_ATTRIB_ARRAY_TYPE`: $(I `params`) returns a single value, a symbolic constant indicating the array type for the vertex attribute array for $(I `index`). Possible values are `BYTE`, `UNSIGNED_BYTE`, `SHORT`, `UNSIGNED_SHORT`, `INT`, `UNSIGNED_INT`, `FLOAT`, and `DOUBLE`. The initial value is `FLOAT`.
	
	- `VERTEX_ATTRIB_ARRAY_NORMALIZED`: $(I `params`) returns a single value that is non-zero (true) if fixed-point data types for the vertex attribute array indicated by $(I `index`) are normalized when they are converted to floating point, and 0 (false) otherwise. The initial value is `FALSE`.
	
	- `VERTEX_ATTRIB_ARRAY_INTEGER`: $(I `params`) returns a single value that is non-zero (true) if fixed-point data types for the vertex attribute array indicated by $(I `index`) have integer data types, and 0 (false) otherwise. The initial value is 0 (`FALSE`).
	
	- `VERTEX_ATTRIB_ARRAY_LONG`: $(I `param`) returns a single value that is non-zero (true) if a vertex attribute is stored as an unconverted double, and 0 (false) otherwise. The initial value is 0 (`FALSE`).
	
	- `VERTEX_ATTRIB_ARRAY_DIVISOR`: $(I `params`) returns a single value that is the frequency divisor used for instanced rendering. See $(REF vertexAttribDivisor). The initial value is 0.
	
	- `VERTEX_ATTRIB_BINDING`: $(I `params`) returns a single value, the vertex buffer binding of the vertex attribute array $(I `index`).
	
	- `VERTEX_ATTRIB_RELATIVE_OFFSET`: $(I `params`) returns a single value that is the byte offset of the first element relative to the start of the vertex buffer binding specified attribute fetches from. The initial value is 0.
	
	- `CURRENT_VERTEX_ATTRIB`: $(I `params`) returns four values that represent the current value for the generic vertex attribute specified by index. Generic vertex attribute 0 is unique in that it has no current state, so an error will be generated if $(I `index`) is 0. The initial value for all other generic vertex attributes is (0,0,0,1).  $(REF getVertexAttribdv) and $(REF getVertexAttribfv) return the current attribute values as four single-precision floating-point values; $(REF getVertexAttribiv) reads them as floating-point values and converts them to four integer values; $(REF getVertexAttribIiv) and $(REF getVertexAttribIuiv) read and return them as signed or unsigned integer values, respectively; $(REF getVertexAttribLdv) reads and returns them as four double-precision floating-point values.
	
	All of the parameters except `CURRENT_VERTEX_ATTRIB` represent state stored in the currently bound vertex array object.
	
	Params:
	index = Specifies the generic vertex attribute parameter to be queried.
	pname = Specifies the symbolic name of the vertex attribute parameter to be queried. Accepted values are `VERTEX_ATTRIB_ARRAY_BUFFER_BINDING`, `VERTEX_ATTRIB_ARRAY_ENABLED`, `VERTEX_ATTRIB_ARRAY_SIZE`, `VERTEX_ATTRIB_ARRAY_STRIDE`, `VERTEX_ATTRIB_ARRAY_TYPE`, `VERTEX_ATTRIB_ARRAY_NORMALIZED`, `VERTEX_ATTRIB_ARRAY_INTEGER`, `VERTEX_ATTRIB_ARRAY_LONG`, `VERTEX_ATTRIB_ARRAY_DIVISOR`, `VERTEX_ATTRIB_BINDING`, `VERTEX_ATTRIB_RELATIVE_OFFSET` or `CURRENT_VERTEX_ATTRIB`.
	params = Returns the requested data.
	*/
	void getVertexAttribiv(UInt index, Enum pname, Int* params);
	
	/**
	$(REF getVertexAttribPointerv) returns pointer information. $(I `index`) is the generic vertex attribute to be queried, $(I `pname`) is a symbolic constant indicating the pointer to be returned, and $(I `params`) is a pointer to a location in which to place the returned data.
	
	The $(I `pointer`) returned is a byte offset into the data store of the buffer object that was bound to the `ARRAY_BUFFER` target (see $(REF bindBuffer)) when the desired pointer was previously specified.
	
	Params:
	index = Specifies the generic vertex attribute parameter to be returned.
	pname = Specifies the symbolic name of the generic vertex attribute parameter to be returned. Must be `VERTEX_ATTRIB_ARRAY_POINTER`.
	pointer = Returns the pointer value.
	*/
	void getVertexAttribPointerv(UInt index, Enum pname, void* pointer);
	
	/**
	$(REF isProgram) returns `TRUE` if $(I `program`) is the name of a program object previously created with $(REF createProgram) and not yet deleted with $(REF deleteProgram). If $(I `program`) is zero or a non-zero value that is not the name of a program object, or if an error occurs, $(REF isProgram) returns `FALSE`.
	
	Params:
	program = Specifies a potential program object.
	*/
	Boolean isProgram(UInt program);
	
	/**
	$(REF isShader) returns `TRUE` if $(I `shader`) is the name of a shader object previously created with $(REF createShader) and not yet deleted with $(REF deleteShader). If $(I `shader`) is zero or a non-zero value that is not the name of a shader object, or if an error occurs, $(REF isShader ) returns `FALSE`.
	
	Params:
	shader = Specifies a potential shader object.
	*/
	Boolean isShader(UInt shader);
	
	/**
	$(REF linkProgram) links the program object specified by $(I `program`). If any shader objects of type `VERTEX_SHADER` are attached to $(I `program`), they will be used to create an executable that will run on the programmable vertex processor. If any shader objects of type `GEOMETRY_SHADER` are attached to $(I `program`), they will be used to create an executable that will run on the programmable geometry processor. If any shader objects of type `FRAGMENT_SHADER` are attached to $(I `program`), they will be used to create an executable that will run on the programmable fragment processor.
	
	The status of the link operation will be stored as part of the program object's state. This value will be set to `TRUE` if the program object was linked without errors and is ready for use, and `FALSE` otherwise. It can be queried by calling $(REF getProgram) with arguments $(I `program`) and `LINK_STATUS`.
	
	As a result of a successful link operation, all active user-defined uniform variables belonging to $(I `program`) will be initialized to 0, and each of the program object's active uniform variables will be assigned a location that can be queried by calling $(REF getUniformLocation). Also, any active user-defined attribute variables that have not been bound to a generic vertex attribute index will be bound to one at this time.
	
	Linking of a program object can fail for a number of reasons as specified in the $(I OpenGL Shading Language Specification). The following lists some of the conditions that will cause a link error.
	
	When a program object has been successfully linked, the program object can be made part of current state by calling $(REF useProgram). Whether or not the link operation was successful, the program object's information log will be overwritten. The information log can be retrieved by calling $(REF getProgramInfoLog).
	
	$(REF linkProgram) will also install the generated executables as part of the current rendering state if the link operation was successful and the specified program object is already currently in use as a result of a previous call to $(REF useProgram). If the program object currently in use is relinked unsuccessfully, its link status will be set to `FALSE` , but the executables and associated state will remain part of the current state until a subsequent call to $(REF useProgram) removes it from use. After it is removed from use, it cannot be made part of current state until it has been successfully relinked.
	
	If $(I `program`) contains shader objects of type `VERTEX_SHADER`, and optionally of type `GEOMETRY_SHADER`, but does not contain shader objects of type `FRAGMENT_SHADER`, the vertex shader executable will be installed on the programmable vertex processor, the geometry shader executable, if present, will be installed on the programmable geometry processor, but no executable will be installed on the fragment processor. The results of rasterizing primitives with such a program will be undefined.
	
	The program object's information log is updated and the program is generated at the time of the link operation. After the link operation, applications are free to modify attached shader objects, compile attached shader objects, detach shader objects, delete shader objects, and attach additional shader objects. None of these operations affects the information log or the program that is part of the program object.
	
	Params:
	program = Specifies the handle of the program object to be linked.
	*/
	void linkProgram(UInt program);
	
	/**
	$(REF shaderSource) sets the source code in $(I `shader`) to the source code in the array of strings specified by $(I `string`). Any source code previously stored in the shader object is completely replaced. The number of strings in the array is specified by $(I `count`). If $(I `length`) is `NULL`, each string is assumed to be null terminated. If $(I `length`) is a value other than `NULL`, it points to an array containing a string length for each of the corresponding elements of $(I `string`). Each element in the $(I `length`) array may contain the length of the corresponding string (the null character is not counted as part of the string length) or a value less than 0 to indicate that the string is null terminated. The source code strings are not scanned or parsed at this time; they are simply copied into the specified shader object.
	
	Params:
	shader = Specifies the handle of the shader object whose source code is to be replaced.
	count = Specifies the number of elements in the $(I `string`) and $(I `length`) arrays.
	string = Specifies an array of pointers to strings containing the source code to be loaded into the shader.
	length = Specifies an array of string lengths.
	*/
	void shaderSource(UInt shader, Sizei count, const(Char*)* string, const(Int)* length);
	
	/**
	$(REF useProgram) installs the program object specified by $(I `program`) as part of current rendering state. One or more executables are created in a program object by successfully attaching shader objects to it with $(REF attachShader), successfully compiling the shader objects with $(REF compileShader), and successfully linking the program object with $(REF linkProgram).
	
	A program object will contain an executable that will run on the vertex processor if it contains one or more shader objects of type `VERTEX_SHADER` that have been successfully compiled and linked. A program object will contain an executable that will run on the geometry processor if it contains one or more shader objects of type `GEOMETRY_SHADER` that have been successfully compiled and linked. Similarly, a program object will contain an executable that will run on the fragment processor if it contains one or more shader objects of type `FRAGMENT_SHADER` that have been successfully compiled and linked.
	
	While a program object is in use, applications are free to modify attached shader objects, compile attached shader objects, attach additional shader objects, and detach or delete shader objects. None of these operations will affect the executables that are part of the current state. However, relinking the program object that is currently in use will install the program object as part of the current rendering state if the link operation was successful (see $(REF linkProgram) ). If the program object currently in use is relinked unsuccessfully, its link status will be set to `FALSE`, but the executables and associated state will remain part of the current state until a subsequent call to $(REF useProgram) removes it from use. After it is removed from use, it cannot be made part of current state until it has been successfully relinked.
	
	If $(I `program`) is zero, then the current rendering state refers to an $(I invalid) program object and the results of shader execution are undefined. However, this is not an error.
	
	If $(I `program`) does not contain shader objects of type `FRAGMENT_SHADER`, an executable will be installed on the vertex, and possibly geometry processors, but the results of fragment shader execution will be undefined.
	
	Params:
	program = Specifies the handle of the program object whose executables are to be used as part of current rendering state.
	*/
	void useProgram(UInt program);
	
	/**
	$(REF uniform) modifies the value of a uniform variable or a uniform variable array. The location of the uniform variable to be modified is specified by $(I `location`), which should be a value returned by $(REF getUniformLocation). $(REF uniform) operates on the program object that was made part of current state by calling $(REF useProgram).
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}) are used to change the value of the uniform variable specified by $(I `location`) using the values passed as arguments. The number specified in the command should match the number of components in the data type of the specified uniform variable (e.g., `1` for `float`, `int`, `unsigned int`, `bool`; `2` for `vec2`, `ivec2`, `uvec2`, `bvec2`, etc.). The suffix `f` indicates that floating-point values are being passed; the suffix `i` indicates that integer values are being passed; the suffix `ui` indicates that unsigned integer values are being passed, and this type should also match the data type of the specified uniform variable. The `i` variants of this function should be used to provide values for uniform variables defined as `int`, `ivec2`, `ivec3`, `ivec4`, or arrays of these. The `ui` variants of this function should be used to provide values for uniform variables defined as `unsigned int`, `uvec2`, `uvec3`, `uvec4`, or arrays of these. The `f` variants should be used to provide values for uniform variables of type `float`, `vec2`, `vec3`, `vec4`, or arrays of these. Either the `i`, `ui` or `f` variants may be used to provide values for uniform variables of type `bool`, `bvec2`, `bvec3`, `bvec4`, or arrays of these. The uniform variable will be set to `false` if the input value is 0 or 0.0f, and it will be set to `true` otherwise.
	
	All active uniform variables defined in a program object are initialized to 0 when the program object is linked successfully. They retain the values assigned to them by a call to $(REF uniform ) until the next successful link operation occurs on the program object, when they are once again initialized to 0.
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}v) can be used to modify a single uniform variable or a uniform variable array. These commands pass a count and a pointer to the values to be loaded into a uniform variable or a uniform variable array. A count of 1 should be used if modifying the value of a single uniform variable, and a count of 1 or greater can be used to modify an entire array or part of an array. When loading $(I n) elements starting at an arbitrary position $(I m) in a uniform variable array, elements $(I m) + $(I n) - 1 in the array will be replaced with the new values. If $(I `m`) + $(I `n`) - 1 is larger than the size of the uniform variable array, values for all array elements beyond the end of the array will be ignored. The number specified in the name of the command indicates the number of components for each element in $(I `value`), and it should match the number of components in the data type of the specified uniform variable (e.g., `1` for float, int, bool; `2` for vec2, ivec2, bvec2, etc.). The data type specified in the name of the command must match the data type for the specified uniform variable as described previously for $(REF uniform{1|2|3|4}{f|i|ui}).
	
	For uniform variable arrays, each element of the array is considered to be of the type indicated in the name of the command (e.g., $(REF uniform3f) or $(REF uniform3fv) can be used to load a uniform variable array of type vec3). The number of elements of the uniform variable array to be modified is specified by $(I `count`)
	
	The commands $(REF uniformMatrix{2|3|4|2x3|3x2|2x4|4x2|3x4|4x3}fv) are used to modify a matrix or an array of matrices. The numbers in the command name are interpreted as the dimensionality of the matrix. The number `2` indicates a 2 × 2 matrix (i.e., 4 values), the number `3` indicates a 3 × 3 matrix (i.e., 9 values), and the number `4` indicates a 4 × 4 matrix (i.e., 16 values). Non-square matrix dimensionality is explicit, with the first number representing the number of columns and the second number representing the number of rows. For example, `2x4` indicates a 2 × 4 matrix with 2 columns and 4 rows (i.e., 8 values). If $(I `transpose`) is `FALSE`, each matrix is assumed to be supplied in column major order. If $(I `transpose`) is `TRUE`, each matrix is assumed to be supplied in row major order. The $(I `count`) argument indicates the number of matrices to be passed. A count of 1 should be used if modifying the value of a single matrix, and a count greater than 1 can be used to modify an array of matrices.
	
	Params:
	location = Specifies the location of the uniform variable to be modified.
	v0 = For the scalar commands, specifies the new values to be used for the specified uniform variable.
	*/
	void uniform1f(Int location, Float v0);
	
	/**
	$(REF uniform) modifies the value of a uniform variable or a uniform variable array. The location of the uniform variable to be modified is specified by $(I `location`), which should be a value returned by $(REF getUniformLocation). $(REF uniform) operates on the program object that was made part of current state by calling $(REF useProgram).
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}) are used to change the value of the uniform variable specified by $(I `location`) using the values passed as arguments. The number specified in the command should match the number of components in the data type of the specified uniform variable (e.g., `1` for `float`, `int`, `unsigned int`, `bool`; `2` for `vec2`, `ivec2`, `uvec2`, `bvec2`, etc.). The suffix `f` indicates that floating-point values are being passed; the suffix `i` indicates that integer values are being passed; the suffix `ui` indicates that unsigned integer values are being passed, and this type should also match the data type of the specified uniform variable. The `i` variants of this function should be used to provide values for uniform variables defined as `int`, `ivec2`, `ivec3`, `ivec4`, or arrays of these. The `ui` variants of this function should be used to provide values for uniform variables defined as `unsigned int`, `uvec2`, `uvec3`, `uvec4`, or arrays of these. The `f` variants should be used to provide values for uniform variables of type `float`, `vec2`, `vec3`, `vec4`, or arrays of these. Either the `i`, `ui` or `f` variants may be used to provide values for uniform variables of type `bool`, `bvec2`, `bvec3`, `bvec4`, or arrays of these. The uniform variable will be set to `false` if the input value is 0 or 0.0f, and it will be set to `true` otherwise.
	
	All active uniform variables defined in a program object are initialized to 0 when the program object is linked successfully. They retain the values assigned to them by a call to $(REF uniform ) until the next successful link operation occurs on the program object, when they are once again initialized to 0.
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}v) can be used to modify a single uniform variable or a uniform variable array. These commands pass a count and a pointer to the values to be loaded into a uniform variable or a uniform variable array. A count of 1 should be used if modifying the value of a single uniform variable, and a count of 1 or greater can be used to modify an entire array or part of an array. When loading $(I n) elements starting at an arbitrary position $(I m) in a uniform variable array, elements $(I m) + $(I n) - 1 in the array will be replaced with the new values. If $(I `m`) + $(I `n`) - 1 is larger than the size of the uniform variable array, values for all array elements beyond the end of the array will be ignored. The number specified in the name of the command indicates the number of components for each element in $(I `value`), and it should match the number of components in the data type of the specified uniform variable (e.g., `1` for float, int, bool; `2` for vec2, ivec2, bvec2, etc.). The data type specified in the name of the command must match the data type for the specified uniform variable as described previously for $(REF uniform{1|2|3|4}{f|i|ui}).
	
	For uniform variable arrays, each element of the array is considered to be of the type indicated in the name of the command (e.g., $(REF uniform3f) or $(REF uniform3fv) can be used to load a uniform variable array of type vec3). The number of elements of the uniform variable array to be modified is specified by $(I `count`)
	
	The commands $(REF uniformMatrix{2|3|4|2x3|3x2|2x4|4x2|3x4|4x3}fv) are used to modify a matrix or an array of matrices. The numbers in the command name are interpreted as the dimensionality of the matrix. The number `2` indicates a 2 × 2 matrix (i.e., 4 values), the number `3` indicates a 3 × 3 matrix (i.e., 9 values), and the number `4` indicates a 4 × 4 matrix (i.e., 16 values). Non-square matrix dimensionality is explicit, with the first number representing the number of columns and the second number representing the number of rows. For example, `2x4` indicates a 2 × 4 matrix with 2 columns and 4 rows (i.e., 8 values). If $(I `transpose`) is `FALSE`, each matrix is assumed to be supplied in column major order. If $(I `transpose`) is `TRUE`, each matrix is assumed to be supplied in row major order. The $(I `count`) argument indicates the number of matrices to be passed. A count of 1 should be used if modifying the value of a single matrix, and a count greater than 1 can be used to modify an array of matrices.
	
	Params:
	location = Specifies the location of the uniform variable to be modified.
	v0 = For the scalar commands, specifies the new values to be used for the specified uniform variable.
	v1 = For the scalar commands, specifies the new values to be used for the specified uniform variable.
	*/
	void uniform2f(Int location, Float v0, Float v1);
	
	/**
	$(REF uniform) modifies the value of a uniform variable or a uniform variable array. The location of the uniform variable to be modified is specified by $(I `location`), which should be a value returned by $(REF getUniformLocation). $(REF uniform) operates on the program object that was made part of current state by calling $(REF useProgram).
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}) are used to change the value of the uniform variable specified by $(I `location`) using the values passed as arguments. The number specified in the command should match the number of components in the data type of the specified uniform variable (e.g., `1` for `float`, `int`, `unsigned int`, `bool`; `2` for `vec2`, `ivec2`, `uvec2`, `bvec2`, etc.). The suffix `f` indicates that floating-point values are being passed; the suffix `i` indicates that integer values are being passed; the suffix `ui` indicates that unsigned integer values are being passed, and this type should also match the data type of the specified uniform variable. The `i` variants of this function should be used to provide values for uniform variables defined as `int`, `ivec2`, `ivec3`, `ivec4`, or arrays of these. The `ui` variants of this function should be used to provide values for uniform variables defined as `unsigned int`, `uvec2`, `uvec3`, `uvec4`, or arrays of these. The `f` variants should be used to provide values for uniform variables of type `float`, `vec2`, `vec3`, `vec4`, or arrays of these. Either the `i`, `ui` or `f` variants may be used to provide values for uniform variables of type `bool`, `bvec2`, `bvec3`, `bvec4`, or arrays of these. The uniform variable will be set to `false` if the input value is 0 or 0.0f, and it will be set to `true` otherwise.
	
	All active uniform variables defined in a program object are initialized to 0 when the program object is linked successfully. They retain the values assigned to them by a call to $(REF uniform ) until the next successful link operation occurs on the program object, when they are once again initialized to 0.
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}v) can be used to modify a single uniform variable or a uniform variable array. These commands pass a count and a pointer to the values to be loaded into a uniform variable or a uniform variable array. A count of 1 should be used if modifying the value of a single uniform variable, and a count of 1 or greater can be used to modify an entire array or part of an array. When loading $(I n) elements starting at an arbitrary position $(I m) in a uniform variable array, elements $(I m) + $(I n) - 1 in the array will be replaced with the new values. If $(I `m`) + $(I `n`) - 1 is larger than the size of the uniform variable array, values for all array elements beyond the end of the array will be ignored. The number specified in the name of the command indicates the number of components for each element in $(I `value`), and it should match the number of components in the data type of the specified uniform variable (e.g., `1` for float, int, bool; `2` for vec2, ivec2, bvec2, etc.). The data type specified in the name of the command must match the data type for the specified uniform variable as described previously for $(REF uniform{1|2|3|4}{f|i|ui}).
	
	For uniform variable arrays, each element of the array is considered to be of the type indicated in the name of the command (e.g., $(REF uniform3f) or $(REF uniform3fv) can be used to load a uniform variable array of type vec3). The number of elements of the uniform variable array to be modified is specified by $(I `count`)
	
	The commands $(REF uniformMatrix{2|3|4|2x3|3x2|2x4|4x2|3x4|4x3}fv) are used to modify a matrix or an array of matrices. The numbers in the command name are interpreted as the dimensionality of the matrix. The number `2` indicates a 2 × 2 matrix (i.e., 4 values), the number `3` indicates a 3 × 3 matrix (i.e., 9 values), and the number `4` indicates a 4 × 4 matrix (i.e., 16 values). Non-square matrix dimensionality is explicit, with the first number representing the number of columns and the second number representing the number of rows. For example, `2x4` indicates a 2 × 4 matrix with 2 columns and 4 rows (i.e., 8 values). If $(I `transpose`) is `FALSE`, each matrix is assumed to be supplied in column major order. If $(I `transpose`) is `TRUE`, each matrix is assumed to be supplied in row major order. The $(I `count`) argument indicates the number of matrices to be passed. A count of 1 should be used if modifying the value of a single matrix, and a count greater than 1 can be used to modify an array of matrices.
	
	Params:
	location = Specifies the location of the uniform variable to be modified.
	v0 = For the scalar commands, specifies the new values to be used for the specified uniform variable.
	v1 = For the scalar commands, specifies the new values to be used for the specified uniform variable.
	v2 = For the scalar commands, specifies the new values to be used for the specified uniform variable.
	*/
	void uniform3f(Int location, Float v0, Float v1, Float v2);
	
	/**
	$(REF uniform) modifies the value of a uniform variable or a uniform variable array. The location of the uniform variable to be modified is specified by $(I `location`), which should be a value returned by $(REF getUniformLocation). $(REF uniform) operates on the program object that was made part of current state by calling $(REF useProgram).
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}) are used to change the value of the uniform variable specified by $(I `location`) using the values passed as arguments. The number specified in the command should match the number of components in the data type of the specified uniform variable (e.g., `1` for `float`, `int`, `unsigned int`, `bool`; `2` for `vec2`, `ivec2`, `uvec2`, `bvec2`, etc.). The suffix `f` indicates that floating-point values are being passed; the suffix `i` indicates that integer values are being passed; the suffix `ui` indicates that unsigned integer values are being passed, and this type should also match the data type of the specified uniform variable. The `i` variants of this function should be used to provide values for uniform variables defined as `int`, `ivec2`, `ivec3`, `ivec4`, or arrays of these. The `ui` variants of this function should be used to provide values for uniform variables defined as `unsigned int`, `uvec2`, `uvec3`, `uvec4`, or arrays of these. The `f` variants should be used to provide values for uniform variables of type `float`, `vec2`, `vec3`, `vec4`, or arrays of these. Either the `i`, `ui` or `f` variants may be used to provide values for uniform variables of type `bool`, `bvec2`, `bvec3`, `bvec4`, or arrays of these. The uniform variable will be set to `false` if the input value is 0 or 0.0f, and it will be set to `true` otherwise.
	
	All active uniform variables defined in a program object are initialized to 0 when the program object is linked successfully. They retain the values assigned to them by a call to $(REF uniform ) until the next successful link operation occurs on the program object, when they are once again initialized to 0.
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}v) can be used to modify a single uniform variable or a uniform variable array. These commands pass a count and a pointer to the values to be loaded into a uniform variable or a uniform variable array. A count of 1 should be used if modifying the value of a single uniform variable, and a count of 1 or greater can be used to modify an entire array or part of an array. When loading $(I n) elements starting at an arbitrary position $(I m) in a uniform variable array, elements $(I m) + $(I n) - 1 in the array will be replaced with the new values. If $(I `m`) + $(I `n`) - 1 is larger than the size of the uniform variable array, values for all array elements beyond the end of the array will be ignored. The number specified in the name of the command indicates the number of components for each element in $(I `value`), and it should match the number of components in the data type of the specified uniform variable (e.g., `1` for float, int, bool; `2` for vec2, ivec2, bvec2, etc.). The data type specified in the name of the command must match the data type for the specified uniform variable as described previously for $(REF uniform{1|2|3|4}{f|i|ui}).
	
	For uniform variable arrays, each element of the array is considered to be of the type indicated in the name of the command (e.g., $(REF uniform3f) or $(REF uniform3fv) can be used to load a uniform variable array of type vec3). The number of elements of the uniform variable array to be modified is specified by $(I `count`)
	
	The commands $(REF uniformMatrix{2|3|4|2x3|3x2|2x4|4x2|3x4|4x3}fv) are used to modify a matrix or an array of matrices. The numbers in the command name are interpreted as the dimensionality of the matrix. The number `2` indicates a 2 × 2 matrix (i.e., 4 values), the number `3` indicates a 3 × 3 matrix (i.e., 9 values), and the number `4` indicates a 4 × 4 matrix (i.e., 16 values). Non-square matrix dimensionality is explicit, with the first number representing the number of columns and the second number representing the number of rows. For example, `2x4` indicates a 2 × 4 matrix with 2 columns and 4 rows (i.e., 8 values). If $(I `transpose`) is `FALSE`, each matrix is assumed to be supplied in column major order. If $(I `transpose`) is `TRUE`, each matrix is assumed to be supplied in row major order. The $(I `count`) argument indicates the number of matrices to be passed. A count of 1 should be used if modifying the value of a single matrix, and a count greater than 1 can be used to modify an array of matrices.
	
	Params:
	location = Specifies the location of the uniform variable to be modified.
	v0 = For the scalar commands, specifies the new values to be used for the specified uniform variable.
	v1 = For the scalar commands, specifies the new values to be used for the specified uniform variable.
	v2 = For the scalar commands, specifies the new values to be used for the specified uniform variable.
	v3 = For the scalar commands, specifies the new values to be used for the specified uniform variable.
	*/
	void uniform4f(Int location, Float v0, Float v1, Float v2, Float v3);
	
	/**
	$(REF uniform) modifies the value of a uniform variable or a uniform variable array. The location of the uniform variable to be modified is specified by $(I `location`), which should be a value returned by $(REF getUniformLocation). $(REF uniform) operates on the program object that was made part of current state by calling $(REF useProgram).
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}) are used to change the value of the uniform variable specified by $(I `location`) using the values passed as arguments. The number specified in the command should match the number of components in the data type of the specified uniform variable (e.g., `1` for `float`, `int`, `unsigned int`, `bool`; `2` for `vec2`, `ivec2`, `uvec2`, `bvec2`, etc.). The suffix `f` indicates that floating-point values are being passed; the suffix `i` indicates that integer values are being passed; the suffix `ui` indicates that unsigned integer values are being passed, and this type should also match the data type of the specified uniform variable. The `i` variants of this function should be used to provide values for uniform variables defined as `int`, `ivec2`, `ivec3`, `ivec4`, or arrays of these. The `ui` variants of this function should be used to provide values for uniform variables defined as `unsigned int`, `uvec2`, `uvec3`, `uvec4`, or arrays of these. The `f` variants should be used to provide values for uniform variables of type `float`, `vec2`, `vec3`, `vec4`, or arrays of these. Either the `i`, `ui` or `f` variants may be used to provide values for uniform variables of type `bool`, `bvec2`, `bvec3`, `bvec4`, or arrays of these. The uniform variable will be set to `false` if the input value is 0 or 0.0f, and it will be set to `true` otherwise.
	
	All active uniform variables defined in a program object are initialized to 0 when the program object is linked successfully. They retain the values assigned to them by a call to $(REF uniform ) until the next successful link operation occurs on the program object, when they are once again initialized to 0.
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}v) can be used to modify a single uniform variable or a uniform variable array. These commands pass a count and a pointer to the values to be loaded into a uniform variable or a uniform variable array. A count of 1 should be used if modifying the value of a single uniform variable, and a count of 1 or greater can be used to modify an entire array or part of an array. When loading $(I n) elements starting at an arbitrary position $(I m) in a uniform variable array, elements $(I m) + $(I n) - 1 in the array will be replaced with the new values. If $(I `m`) + $(I `n`) - 1 is larger than the size of the uniform variable array, values for all array elements beyond the end of the array will be ignored. The number specified in the name of the command indicates the number of components for each element in $(I `value`), and it should match the number of components in the data type of the specified uniform variable (e.g., `1` for float, int, bool; `2` for vec2, ivec2, bvec2, etc.). The data type specified in the name of the command must match the data type for the specified uniform variable as described previously for $(REF uniform{1|2|3|4}{f|i|ui}).
	
	For uniform variable arrays, each element of the array is considered to be of the type indicated in the name of the command (e.g., $(REF uniform3f) or $(REF uniform3fv) can be used to load a uniform variable array of type vec3). The number of elements of the uniform variable array to be modified is specified by $(I `count`)
	
	The commands $(REF uniformMatrix{2|3|4|2x3|3x2|2x4|4x2|3x4|4x3}fv) are used to modify a matrix or an array of matrices. The numbers in the command name are interpreted as the dimensionality of the matrix. The number `2` indicates a 2 × 2 matrix (i.e., 4 values), the number `3` indicates a 3 × 3 matrix (i.e., 9 values), and the number `4` indicates a 4 × 4 matrix (i.e., 16 values). Non-square matrix dimensionality is explicit, with the first number representing the number of columns and the second number representing the number of rows. For example, `2x4` indicates a 2 × 4 matrix with 2 columns and 4 rows (i.e., 8 values). If $(I `transpose`) is `FALSE`, each matrix is assumed to be supplied in column major order. If $(I `transpose`) is `TRUE`, each matrix is assumed to be supplied in row major order. The $(I `count`) argument indicates the number of matrices to be passed. A count of 1 should be used if modifying the value of a single matrix, and a count greater than 1 can be used to modify an array of matrices.
	
	Params:
	location = Specifies the location of the uniform variable to be modified.
	v0 = For the scalar commands, specifies the new values to be used for the specified uniform variable.
	*/
	void uniform1i(Int location, Int v0);
	
	/**
	$(REF uniform) modifies the value of a uniform variable or a uniform variable array. The location of the uniform variable to be modified is specified by $(I `location`), which should be a value returned by $(REF getUniformLocation). $(REF uniform) operates on the program object that was made part of current state by calling $(REF useProgram).
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}) are used to change the value of the uniform variable specified by $(I `location`) using the values passed as arguments. The number specified in the command should match the number of components in the data type of the specified uniform variable (e.g., `1` for `float`, `int`, `unsigned int`, `bool`; `2` for `vec2`, `ivec2`, `uvec2`, `bvec2`, etc.). The suffix `f` indicates that floating-point values are being passed; the suffix `i` indicates that integer values are being passed; the suffix `ui` indicates that unsigned integer values are being passed, and this type should also match the data type of the specified uniform variable. The `i` variants of this function should be used to provide values for uniform variables defined as `int`, `ivec2`, `ivec3`, `ivec4`, or arrays of these. The `ui` variants of this function should be used to provide values for uniform variables defined as `unsigned int`, `uvec2`, `uvec3`, `uvec4`, or arrays of these. The `f` variants should be used to provide values for uniform variables of type `float`, `vec2`, `vec3`, `vec4`, or arrays of these. Either the `i`, `ui` or `f` variants may be used to provide values for uniform variables of type `bool`, `bvec2`, `bvec3`, `bvec4`, or arrays of these. The uniform variable will be set to `false` if the input value is 0 or 0.0f, and it will be set to `true` otherwise.
	
	All active uniform variables defined in a program object are initialized to 0 when the program object is linked successfully. They retain the values assigned to them by a call to $(REF uniform ) until the next successful link operation occurs on the program object, when they are once again initialized to 0.
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}v) can be used to modify a single uniform variable or a uniform variable array. These commands pass a count and a pointer to the values to be loaded into a uniform variable or a uniform variable array. A count of 1 should be used if modifying the value of a single uniform variable, and a count of 1 or greater can be used to modify an entire array or part of an array. When loading $(I n) elements starting at an arbitrary position $(I m) in a uniform variable array, elements $(I m) + $(I n) - 1 in the array will be replaced with the new values. If $(I `m`) + $(I `n`) - 1 is larger than the size of the uniform variable array, values for all array elements beyond the end of the array will be ignored. The number specified in the name of the command indicates the number of components for each element in $(I `value`), and it should match the number of components in the data type of the specified uniform variable (e.g., `1` for float, int, bool; `2` for vec2, ivec2, bvec2, etc.). The data type specified in the name of the command must match the data type for the specified uniform variable as described previously for $(REF uniform{1|2|3|4}{f|i|ui}).
	
	For uniform variable arrays, each element of the array is considered to be of the type indicated in the name of the command (e.g., $(REF uniform3f) or $(REF uniform3fv) can be used to load a uniform variable array of type vec3). The number of elements of the uniform variable array to be modified is specified by $(I `count`)
	
	The commands $(REF uniformMatrix{2|3|4|2x3|3x2|2x4|4x2|3x4|4x3}fv) are used to modify a matrix or an array of matrices. The numbers in the command name are interpreted as the dimensionality of the matrix. The number `2` indicates a 2 × 2 matrix (i.e., 4 values), the number `3` indicates a 3 × 3 matrix (i.e., 9 values), and the number `4` indicates a 4 × 4 matrix (i.e., 16 values). Non-square matrix dimensionality is explicit, with the first number representing the number of columns and the second number representing the number of rows. For example, `2x4` indicates a 2 × 4 matrix with 2 columns and 4 rows (i.e., 8 values). If $(I `transpose`) is `FALSE`, each matrix is assumed to be supplied in column major order. If $(I `transpose`) is `TRUE`, each matrix is assumed to be supplied in row major order. The $(I `count`) argument indicates the number of matrices to be passed. A count of 1 should be used if modifying the value of a single matrix, and a count greater than 1 can be used to modify an array of matrices.
	
	Params:
	location = Specifies the location of the uniform variable to be modified.
	v0 = For the scalar commands, specifies the new values to be used for the specified uniform variable.
	v1 = For the scalar commands, specifies the new values to be used for the specified uniform variable.
	*/
	void uniform2i(Int location, Int v0, Int v1);
	
	/**
	$(REF uniform) modifies the value of a uniform variable or a uniform variable array. The location of the uniform variable to be modified is specified by $(I `location`), which should be a value returned by $(REF getUniformLocation). $(REF uniform) operates on the program object that was made part of current state by calling $(REF useProgram).
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}) are used to change the value of the uniform variable specified by $(I `location`) using the values passed as arguments. The number specified in the command should match the number of components in the data type of the specified uniform variable (e.g., `1` for `float`, `int`, `unsigned int`, `bool`; `2` for `vec2`, `ivec2`, `uvec2`, `bvec2`, etc.). The suffix `f` indicates that floating-point values are being passed; the suffix `i` indicates that integer values are being passed; the suffix `ui` indicates that unsigned integer values are being passed, and this type should also match the data type of the specified uniform variable. The `i` variants of this function should be used to provide values for uniform variables defined as `int`, `ivec2`, `ivec3`, `ivec4`, or arrays of these. The `ui` variants of this function should be used to provide values for uniform variables defined as `unsigned int`, `uvec2`, `uvec3`, `uvec4`, or arrays of these. The `f` variants should be used to provide values for uniform variables of type `float`, `vec2`, `vec3`, `vec4`, or arrays of these. Either the `i`, `ui` or `f` variants may be used to provide values for uniform variables of type `bool`, `bvec2`, `bvec3`, `bvec4`, or arrays of these. The uniform variable will be set to `false` if the input value is 0 or 0.0f, and it will be set to `true` otherwise.
	
	All active uniform variables defined in a program object are initialized to 0 when the program object is linked successfully. They retain the values assigned to them by a call to $(REF uniform ) until the next successful link operation occurs on the program object, when they are once again initialized to 0.
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}v) can be used to modify a single uniform variable or a uniform variable array. These commands pass a count and a pointer to the values to be loaded into a uniform variable or a uniform variable array. A count of 1 should be used if modifying the value of a single uniform variable, and a count of 1 or greater can be used to modify an entire array or part of an array. When loading $(I n) elements starting at an arbitrary position $(I m) in a uniform variable array, elements $(I m) + $(I n) - 1 in the array will be replaced with the new values. If $(I `m`) + $(I `n`) - 1 is larger than the size of the uniform variable array, values for all array elements beyond the end of the array will be ignored. The number specified in the name of the command indicates the number of components for each element in $(I `value`), and it should match the number of components in the data type of the specified uniform variable (e.g., `1` for float, int, bool; `2` for vec2, ivec2, bvec2, etc.). The data type specified in the name of the command must match the data type for the specified uniform variable as described previously for $(REF uniform{1|2|3|4}{f|i|ui}).
	
	For uniform variable arrays, each element of the array is considered to be of the type indicated in the name of the command (e.g., $(REF uniform3f) or $(REF uniform3fv) can be used to load a uniform variable array of type vec3). The number of elements of the uniform variable array to be modified is specified by $(I `count`)
	
	The commands $(REF uniformMatrix{2|3|4|2x3|3x2|2x4|4x2|3x4|4x3}fv) are used to modify a matrix or an array of matrices. The numbers in the command name are interpreted as the dimensionality of the matrix. The number `2` indicates a 2 × 2 matrix (i.e., 4 values), the number `3` indicates a 3 × 3 matrix (i.e., 9 values), and the number `4` indicates a 4 × 4 matrix (i.e., 16 values). Non-square matrix dimensionality is explicit, with the first number representing the number of columns and the second number representing the number of rows. For example, `2x4` indicates a 2 × 4 matrix with 2 columns and 4 rows (i.e., 8 values). If $(I `transpose`) is `FALSE`, each matrix is assumed to be supplied in column major order. If $(I `transpose`) is `TRUE`, each matrix is assumed to be supplied in row major order. The $(I `count`) argument indicates the number of matrices to be passed. A count of 1 should be used if modifying the value of a single matrix, and a count greater than 1 can be used to modify an array of matrices.
	
	Params:
	location = Specifies the location of the uniform variable to be modified.
	v0 = For the scalar commands, specifies the new values to be used for the specified uniform variable.
	v1 = For the scalar commands, specifies the new values to be used for the specified uniform variable.
	v2 = For the scalar commands, specifies the new values to be used for the specified uniform variable.
	*/
	void uniform3i(Int location, Int v0, Int v1, Int v2);
	
	/**
	$(REF uniform) modifies the value of a uniform variable or a uniform variable array. The location of the uniform variable to be modified is specified by $(I `location`), which should be a value returned by $(REF getUniformLocation). $(REF uniform) operates on the program object that was made part of current state by calling $(REF useProgram).
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}) are used to change the value of the uniform variable specified by $(I `location`) using the values passed as arguments. The number specified in the command should match the number of components in the data type of the specified uniform variable (e.g., `1` for `float`, `int`, `unsigned int`, `bool`; `2` for `vec2`, `ivec2`, `uvec2`, `bvec2`, etc.). The suffix `f` indicates that floating-point values are being passed; the suffix `i` indicates that integer values are being passed; the suffix `ui` indicates that unsigned integer values are being passed, and this type should also match the data type of the specified uniform variable. The `i` variants of this function should be used to provide values for uniform variables defined as `int`, `ivec2`, `ivec3`, `ivec4`, or arrays of these. The `ui` variants of this function should be used to provide values for uniform variables defined as `unsigned int`, `uvec2`, `uvec3`, `uvec4`, or arrays of these. The `f` variants should be used to provide values for uniform variables of type `float`, `vec2`, `vec3`, `vec4`, or arrays of these. Either the `i`, `ui` or `f` variants may be used to provide values for uniform variables of type `bool`, `bvec2`, `bvec3`, `bvec4`, or arrays of these. The uniform variable will be set to `false` if the input value is 0 or 0.0f, and it will be set to `true` otherwise.
	
	All active uniform variables defined in a program object are initialized to 0 when the program object is linked successfully. They retain the values assigned to them by a call to $(REF uniform ) until the next successful link operation occurs on the program object, when they are once again initialized to 0.
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}v) can be used to modify a single uniform variable or a uniform variable array. These commands pass a count and a pointer to the values to be loaded into a uniform variable or a uniform variable array. A count of 1 should be used if modifying the value of a single uniform variable, and a count of 1 or greater can be used to modify an entire array or part of an array. When loading $(I n) elements starting at an arbitrary position $(I m) in a uniform variable array, elements $(I m) + $(I n) - 1 in the array will be replaced with the new values. If $(I `m`) + $(I `n`) - 1 is larger than the size of the uniform variable array, values for all array elements beyond the end of the array will be ignored. The number specified in the name of the command indicates the number of components for each element in $(I `value`), and it should match the number of components in the data type of the specified uniform variable (e.g., `1` for float, int, bool; `2` for vec2, ivec2, bvec2, etc.). The data type specified in the name of the command must match the data type for the specified uniform variable as described previously for $(REF uniform{1|2|3|4}{f|i|ui}).
	
	For uniform variable arrays, each element of the array is considered to be of the type indicated in the name of the command (e.g., $(REF uniform3f) or $(REF uniform3fv) can be used to load a uniform variable array of type vec3). The number of elements of the uniform variable array to be modified is specified by $(I `count`)
	
	The commands $(REF uniformMatrix{2|3|4|2x3|3x2|2x4|4x2|3x4|4x3}fv) are used to modify a matrix or an array of matrices. The numbers in the command name are interpreted as the dimensionality of the matrix. The number `2` indicates a 2 × 2 matrix (i.e., 4 values), the number `3` indicates a 3 × 3 matrix (i.e., 9 values), and the number `4` indicates a 4 × 4 matrix (i.e., 16 values). Non-square matrix dimensionality is explicit, with the first number representing the number of columns and the second number representing the number of rows. For example, `2x4` indicates a 2 × 4 matrix with 2 columns and 4 rows (i.e., 8 values). If $(I `transpose`) is `FALSE`, each matrix is assumed to be supplied in column major order. If $(I `transpose`) is `TRUE`, each matrix is assumed to be supplied in row major order. The $(I `count`) argument indicates the number of matrices to be passed. A count of 1 should be used if modifying the value of a single matrix, and a count greater than 1 can be used to modify an array of matrices.
	
	Params:
	location = Specifies the location of the uniform variable to be modified.
	v0 = For the scalar commands, specifies the new values to be used for the specified uniform variable.
	v1 = For the scalar commands, specifies the new values to be used for the specified uniform variable.
	v2 = For the scalar commands, specifies the new values to be used for the specified uniform variable.
	v3 = For the scalar commands, specifies the new values to be used for the specified uniform variable.
	*/
	void uniform4i(Int location, Int v0, Int v1, Int v2, Int v3);
	
	/**
	$(REF uniform) modifies the value of a uniform variable or a uniform variable array. The location of the uniform variable to be modified is specified by $(I `location`), which should be a value returned by $(REF getUniformLocation). $(REF uniform) operates on the program object that was made part of current state by calling $(REF useProgram).
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}) are used to change the value of the uniform variable specified by $(I `location`) using the values passed as arguments. The number specified in the command should match the number of components in the data type of the specified uniform variable (e.g., `1` for `float`, `int`, `unsigned int`, `bool`; `2` for `vec2`, `ivec2`, `uvec2`, `bvec2`, etc.). The suffix `f` indicates that floating-point values are being passed; the suffix `i` indicates that integer values are being passed; the suffix `ui` indicates that unsigned integer values are being passed, and this type should also match the data type of the specified uniform variable. The `i` variants of this function should be used to provide values for uniform variables defined as `int`, `ivec2`, `ivec3`, `ivec4`, or arrays of these. The `ui` variants of this function should be used to provide values for uniform variables defined as `unsigned int`, `uvec2`, `uvec3`, `uvec4`, or arrays of these. The `f` variants should be used to provide values for uniform variables of type `float`, `vec2`, `vec3`, `vec4`, or arrays of these. Either the `i`, `ui` or `f` variants may be used to provide values for uniform variables of type `bool`, `bvec2`, `bvec3`, `bvec4`, or arrays of these. The uniform variable will be set to `false` if the input value is 0 or 0.0f, and it will be set to `true` otherwise.
	
	All active uniform variables defined in a program object are initialized to 0 when the program object is linked successfully. They retain the values assigned to them by a call to $(REF uniform ) until the next successful link operation occurs on the program object, when they are once again initialized to 0.
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}v) can be used to modify a single uniform variable or a uniform variable array. These commands pass a count and a pointer to the values to be loaded into a uniform variable or a uniform variable array. A count of 1 should be used if modifying the value of a single uniform variable, and a count of 1 or greater can be used to modify an entire array or part of an array. When loading $(I n) elements starting at an arbitrary position $(I m) in a uniform variable array, elements $(I m) + $(I n) - 1 in the array will be replaced with the new values. If $(I `m`) + $(I `n`) - 1 is larger than the size of the uniform variable array, values for all array elements beyond the end of the array will be ignored. The number specified in the name of the command indicates the number of components for each element in $(I `value`), and it should match the number of components in the data type of the specified uniform variable (e.g., `1` for float, int, bool; `2` for vec2, ivec2, bvec2, etc.). The data type specified in the name of the command must match the data type for the specified uniform variable as described previously for $(REF uniform{1|2|3|4}{f|i|ui}).
	
	For uniform variable arrays, each element of the array is considered to be of the type indicated in the name of the command (e.g., $(REF uniform3f) or $(REF uniform3fv) can be used to load a uniform variable array of type vec3). The number of elements of the uniform variable array to be modified is specified by $(I `count`)
	
	The commands $(REF uniformMatrix{2|3|4|2x3|3x2|2x4|4x2|3x4|4x3}fv) are used to modify a matrix or an array of matrices. The numbers in the command name are interpreted as the dimensionality of the matrix. The number `2` indicates a 2 × 2 matrix (i.e., 4 values), the number `3` indicates a 3 × 3 matrix (i.e., 9 values), and the number `4` indicates a 4 × 4 matrix (i.e., 16 values). Non-square matrix dimensionality is explicit, with the first number representing the number of columns and the second number representing the number of rows. For example, `2x4` indicates a 2 × 4 matrix with 2 columns and 4 rows (i.e., 8 values). If $(I `transpose`) is `FALSE`, each matrix is assumed to be supplied in column major order. If $(I `transpose`) is `TRUE`, each matrix is assumed to be supplied in row major order. The $(I `count`) argument indicates the number of matrices to be passed. A count of 1 should be used if modifying the value of a single matrix, and a count greater than 1 can be used to modify an array of matrices.
	
	Params:
	location = Specifies the location of the uniform variable to be modified.
	count = For the vector ($(REF uniform*v)) commands, specifies the number of elements that are to be modified. This should be 1 if the targeted uniform variable is not an array, and 1 or more if it is an array. 
	
	 For the matrix ($(REF uniformMatrix*)) commands, specifies the number of matrices that are to be modified. This should be 1 if the targeted uniform variable is not an array of matrices, and 1 or more if it is an array of matrices.
	value = For the vector and matrix commands, specifies a pointer to an array of $(I `count`) values that will be used to update the specified uniform variable.
	*/
	void uniform1fv(Int location, Sizei count, const(Float)* value);
	
	/**
	$(REF uniform) modifies the value of a uniform variable or a uniform variable array. The location of the uniform variable to be modified is specified by $(I `location`), which should be a value returned by $(REF getUniformLocation). $(REF uniform) operates on the program object that was made part of current state by calling $(REF useProgram).
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}) are used to change the value of the uniform variable specified by $(I `location`) using the values passed as arguments. The number specified in the command should match the number of components in the data type of the specified uniform variable (e.g., `1` for `float`, `int`, `unsigned int`, `bool`; `2` for `vec2`, `ivec2`, `uvec2`, `bvec2`, etc.). The suffix `f` indicates that floating-point values are being passed; the suffix `i` indicates that integer values are being passed; the suffix `ui` indicates that unsigned integer values are being passed, and this type should also match the data type of the specified uniform variable. The `i` variants of this function should be used to provide values for uniform variables defined as `int`, `ivec2`, `ivec3`, `ivec4`, or arrays of these. The `ui` variants of this function should be used to provide values for uniform variables defined as `unsigned int`, `uvec2`, `uvec3`, `uvec4`, or arrays of these. The `f` variants should be used to provide values for uniform variables of type `float`, `vec2`, `vec3`, `vec4`, or arrays of these. Either the `i`, `ui` or `f` variants may be used to provide values for uniform variables of type `bool`, `bvec2`, `bvec3`, `bvec4`, or arrays of these. The uniform variable will be set to `false` if the input value is 0 or 0.0f, and it will be set to `true` otherwise.
	
	All active uniform variables defined in a program object are initialized to 0 when the program object is linked successfully. They retain the values assigned to them by a call to $(REF uniform ) until the next successful link operation occurs on the program object, when they are once again initialized to 0.
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}v) can be used to modify a single uniform variable or a uniform variable array. These commands pass a count and a pointer to the values to be loaded into a uniform variable or a uniform variable array. A count of 1 should be used if modifying the value of a single uniform variable, and a count of 1 or greater can be used to modify an entire array or part of an array. When loading $(I n) elements starting at an arbitrary position $(I m) in a uniform variable array, elements $(I m) + $(I n) - 1 in the array will be replaced with the new values. If $(I `m`) + $(I `n`) - 1 is larger than the size of the uniform variable array, values for all array elements beyond the end of the array will be ignored. The number specified in the name of the command indicates the number of components for each element in $(I `value`), and it should match the number of components in the data type of the specified uniform variable (e.g., `1` for float, int, bool; `2` for vec2, ivec2, bvec2, etc.). The data type specified in the name of the command must match the data type for the specified uniform variable as described previously for $(REF uniform{1|2|3|4}{f|i|ui}).
	
	For uniform variable arrays, each element of the array is considered to be of the type indicated in the name of the command (e.g., $(REF uniform3f) or $(REF uniform3fv) can be used to load a uniform variable array of type vec3). The number of elements of the uniform variable array to be modified is specified by $(I `count`)
	
	The commands $(REF uniformMatrix{2|3|4|2x3|3x2|2x4|4x2|3x4|4x3}fv) are used to modify a matrix or an array of matrices. The numbers in the command name are interpreted as the dimensionality of the matrix. The number `2` indicates a 2 × 2 matrix (i.e., 4 values), the number `3` indicates a 3 × 3 matrix (i.e., 9 values), and the number `4` indicates a 4 × 4 matrix (i.e., 16 values). Non-square matrix dimensionality is explicit, with the first number representing the number of columns and the second number representing the number of rows. For example, `2x4` indicates a 2 × 4 matrix with 2 columns and 4 rows (i.e., 8 values). If $(I `transpose`) is `FALSE`, each matrix is assumed to be supplied in column major order. If $(I `transpose`) is `TRUE`, each matrix is assumed to be supplied in row major order. The $(I `count`) argument indicates the number of matrices to be passed. A count of 1 should be used if modifying the value of a single matrix, and a count greater than 1 can be used to modify an array of matrices.
	
	Params:
	location = Specifies the location of the uniform variable to be modified.
	count = For the vector ($(REF uniform*v)) commands, specifies the number of elements that are to be modified. This should be 1 if the targeted uniform variable is not an array, and 1 or more if it is an array. 
	
	 For the matrix ($(REF uniformMatrix*)) commands, specifies the number of matrices that are to be modified. This should be 1 if the targeted uniform variable is not an array of matrices, and 1 or more if it is an array of matrices.
	value = For the vector and matrix commands, specifies a pointer to an array of $(I `count`) values that will be used to update the specified uniform variable.
	*/
	void uniform2fv(Int location, Sizei count, const(Float)* value);
	
	/**
	$(REF uniform) modifies the value of a uniform variable or a uniform variable array. The location of the uniform variable to be modified is specified by $(I `location`), which should be a value returned by $(REF getUniformLocation). $(REF uniform) operates on the program object that was made part of current state by calling $(REF useProgram).
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}) are used to change the value of the uniform variable specified by $(I `location`) using the values passed as arguments. The number specified in the command should match the number of components in the data type of the specified uniform variable (e.g., `1` for `float`, `int`, `unsigned int`, `bool`; `2` for `vec2`, `ivec2`, `uvec2`, `bvec2`, etc.). The suffix `f` indicates that floating-point values are being passed; the suffix `i` indicates that integer values are being passed; the suffix `ui` indicates that unsigned integer values are being passed, and this type should also match the data type of the specified uniform variable. The `i` variants of this function should be used to provide values for uniform variables defined as `int`, `ivec2`, `ivec3`, `ivec4`, or arrays of these. The `ui` variants of this function should be used to provide values for uniform variables defined as `unsigned int`, `uvec2`, `uvec3`, `uvec4`, or arrays of these. The `f` variants should be used to provide values for uniform variables of type `float`, `vec2`, `vec3`, `vec4`, or arrays of these. Either the `i`, `ui` or `f` variants may be used to provide values for uniform variables of type `bool`, `bvec2`, `bvec3`, `bvec4`, or arrays of these. The uniform variable will be set to `false` if the input value is 0 or 0.0f, and it will be set to `true` otherwise.
	
	All active uniform variables defined in a program object are initialized to 0 when the program object is linked successfully. They retain the values assigned to them by a call to $(REF uniform ) until the next successful link operation occurs on the program object, when they are once again initialized to 0.
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}v) can be used to modify a single uniform variable or a uniform variable array. These commands pass a count and a pointer to the values to be loaded into a uniform variable or a uniform variable array. A count of 1 should be used if modifying the value of a single uniform variable, and a count of 1 or greater can be used to modify an entire array or part of an array. When loading $(I n) elements starting at an arbitrary position $(I m) in a uniform variable array, elements $(I m) + $(I n) - 1 in the array will be replaced with the new values. If $(I `m`) + $(I `n`) - 1 is larger than the size of the uniform variable array, values for all array elements beyond the end of the array will be ignored. The number specified in the name of the command indicates the number of components for each element in $(I `value`), and it should match the number of components in the data type of the specified uniform variable (e.g., `1` for float, int, bool; `2` for vec2, ivec2, bvec2, etc.). The data type specified in the name of the command must match the data type for the specified uniform variable as described previously for $(REF uniform{1|2|3|4}{f|i|ui}).
	
	For uniform variable arrays, each element of the array is considered to be of the type indicated in the name of the command (e.g., $(REF uniform3f) or $(REF uniform3fv) can be used to load a uniform variable array of type vec3). The number of elements of the uniform variable array to be modified is specified by $(I `count`)
	
	The commands $(REF uniformMatrix{2|3|4|2x3|3x2|2x4|4x2|3x4|4x3}fv) are used to modify a matrix or an array of matrices. The numbers in the command name are interpreted as the dimensionality of the matrix. The number `2` indicates a 2 × 2 matrix (i.e., 4 values), the number `3` indicates a 3 × 3 matrix (i.e., 9 values), and the number `4` indicates a 4 × 4 matrix (i.e., 16 values). Non-square matrix dimensionality is explicit, with the first number representing the number of columns and the second number representing the number of rows. For example, `2x4` indicates a 2 × 4 matrix with 2 columns and 4 rows (i.e., 8 values). If $(I `transpose`) is `FALSE`, each matrix is assumed to be supplied in column major order. If $(I `transpose`) is `TRUE`, each matrix is assumed to be supplied in row major order. The $(I `count`) argument indicates the number of matrices to be passed. A count of 1 should be used if modifying the value of a single matrix, and a count greater than 1 can be used to modify an array of matrices.
	
	Params:
	location = Specifies the location of the uniform variable to be modified.
	count = For the vector ($(REF uniform*v)) commands, specifies the number of elements that are to be modified. This should be 1 if the targeted uniform variable is not an array, and 1 or more if it is an array. 
	
	 For the matrix ($(REF uniformMatrix*)) commands, specifies the number of matrices that are to be modified. This should be 1 if the targeted uniform variable is not an array of matrices, and 1 or more if it is an array of matrices.
	value = For the vector and matrix commands, specifies a pointer to an array of $(I `count`) values that will be used to update the specified uniform variable.
	*/
	void uniform3fv(Int location, Sizei count, const(Float)* value);
	
	/**
	$(REF uniform) modifies the value of a uniform variable or a uniform variable array. The location of the uniform variable to be modified is specified by $(I `location`), which should be a value returned by $(REF getUniformLocation). $(REF uniform) operates on the program object that was made part of current state by calling $(REF useProgram).
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}) are used to change the value of the uniform variable specified by $(I `location`) using the values passed as arguments. The number specified in the command should match the number of components in the data type of the specified uniform variable (e.g., `1` for `float`, `int`, `unsigned int`, `bool`; `2` for `vec2`, `ivec2`, `uvec2`, `bvec2`, etc.). The suffix `f` indicates that floating-point values are being passed; the suffix `i` indicates that integer values are being passed; the suffix `ui` indicates that unsigned integer values are being passed, and this type should also match the data type of the specified uniform variable. The `i` variants of this function should be used to provide values for uniform variables defined as `int`, `ivec2`, `ivec3`, `ivec4`, or arrays of these. The `ui` variants of this function should be used to provide values for uniform variables defined as `unsigned int`, `uvec2`, `uvec3`, `uvec4`, or arrays of these. The `f` variants should be used to provide values for uniform variables of type `float`, `vec2`, `vec3`, `vec4`, or arrays of these. Either the `i`, `ui` or `f` variants may be used to provide values for uniform variables of type `bool`, `bvec2`, `bvec3`, `bvec4`, or arrays of these. The uniform variable will be set to `false` if the input value is 0 or 0.0f, and it will be set to `true` otherwise.
	
	All active uniform variables defined in a program object are initialized to 0 when the program object is linked successfully. They retain the values assigned to them by a call to $(REF uniform ) until the next successful link operation occurs on the program object, when they are once again initialized to 0.
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}v) can be used to modify a single uniform variable or a uniform variable array. These commands pass a count and a pointer to the values to be loaded into a uniform variable or a uniform variable array. A count of 1 should be used if modifying the value of a single uniform variable, and a count of 1 or greater can be used to modify an entire array or part of an array. When loading $(I n) elements starting at an arbitrary position $(I m) in a uniform variable array, elements $(I m) + $(I n) - 1 in the array will be replaced with the new values. If $(I `m`) + $(I `n`) - 1 is larger than the size of the uniform variable array, values for all array elements beyond the end of the array will be ignored. The number specified in the name of the command indicates the number of components for each element in $(I `value`), and it should match the number of components in the data type of the specified uniform variable (e.g., `1` for float, int, bool; `2` for vec2, ivec2, bvec2, etc.). The data type specified in the name of the command must match the data type for the specified uniform variable as described previously for $(REF uniform{1|2|3|4}{f|i|ui}).
	
	For uniform variable arrays, each element of the array is considered to be of the type indicated in the name of the command (e.g., $(REF uniform3f) or $(REF uniform3fv) can be used to load a uniform variable array of type vec3). The number of elements of the uniform variable array to be modified is specified by $(I `count`)
	
	The commands $(REF uniformMatrix{2|3|4|2x3|3x2|2x4|4x2|3x4|4x3}fv) are used to modify a matrix or an array of matrices. The numbers in the command name are interpreted as the dimensionality of the matrix. The number `2` indicates a 2 × 2 matrix (i.e., 4 values), the number `3` indicates a 3 × 3 matrix (i.e., 9 values), and the number `4` indicates a 4 × 4 matrix (i.e., 16 values). Non-square matrix dimensionality is explicit, with the first number representing the number of columns and the second number representing the number of rows. For example, `2x4` indicates a 2 × 4 matrix with 2 columns and 4 rows (i.e., 8 values). If $(I `transpose`) is `FALSE`, each matrix is assumed to be supplied in column major order. If $(I `transpose`) is `TRUE`, each matrix is assumed to be supplied in row major order. The $(I `count`) argument indicates the number of matrices to be passed. A count of 1 should be used if modifying the value of a single matrix, and a count greater than 1 can be used to modify an array of matrices.
	
	Params:
	location = Specifies the location of the uniform variable to be modified.
	count = For the vector ($(REF uniform*v)) commands, specifies the number of elements that are to be modified. This should be 1 if the targeted uniform variable is not an array, and 1 or more if it is an array. 
	
	 For the matrix ($(REF uniformMatrix*)) commands, specifies the number of matrices that are to be modified. This should be 1 if the targeted uniform variable is not an array of matrices, and 1 or more if it is an array of matrices.
	value = For the vector and matrix commands, specifies a pointer to an array of $(I `count`) values that will be used to update the specified uniform variable.
	*/
	void uniform4fv(Int location, Sizei count, const(Float)* value);
	
	/**
	$(REF uniform) modifies the value of a uniform variable or a uniform variable array. The location of the uniform variable to be modified is specified by $(I `location`), which should be a value returned by $(REF getUniformLocation). $(REF uniform) operates on the program object that was made part of current state by calling $(REF useProgram).
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}) are used to change the value of the uniform variable specified by $(I `location`) using the values passed as arguments. The number specified in the command should match the number of components in the data type of the specified uniform variable (e.g., `1` for `float`, `int`, `unsigned int`, `bool`; `2` for `vec2`, `ivec2`, `uvec2`, `bvec2`, etc.). The suffix `f` indicates that floating-point values are being passed; the suffix `i` indicates that integer values are being passed; the suffix `ui` indicates that unsigned integer values are being passed, and this type should also match the data type of the specified uniform variable. The `i` variants of this function should be used to provide values for uniform variables defined as `int`, `ivec2`, `ivec3`, `ivec4`, or arrays of these. The `ui` variants of this function should be used to provide values for uniform variables defined as `unsigned int`, `uvec2`, `uvec3`, `uvec4`, or arrays of these. The `f` variants should be used to provide values for uniform variables of type `float`, `vec2`, `vec3`, `vec4`, or arrays of these. Either the `i`, `ui` or `f` variants may be used to provide values for uniform variables of type `bool`, `bvec2`, `bvec3`, `bvec4`, or arrays of these. The uniform variable will be set to `false` if the input value is 0 or 0.0f, and it will be set to `true` otherwise.
	
	All active uniform variables defined in a program object are initialized to 0 when the program object is linked successfully. They retain the values assigned to them by a call to $(REF uniform ) until the next successful link operation occurs on the program object, when they are once again initialized to 0.
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}v) can be used to modify a single uniform variable or a uniform variable array. These commands pass a count and a pointer to the values to be loaded into a uniform variable or a uniform variable array. A count of 1 should be used if modifying the value of a single uniform variable, and a count of 1 or greater can be used to modify an entire array or part of an array. When loading $(I n) elements starting at an arbitrary position $(I m) in a uniform variable array, elements $(I m) + $(I n) - 1 in the array will be replaced with the new values. If $(I `m`) + $(I `n`) - 1 is larger than the size of the uniform variable array, values for all array elements beyond the end of the array will be ignored. The number specified in the name of the command indicates the number of components for each element in $(I `value`), and it should match the number of components in the data type of the specified uniform variable (e.g., `1` for float, int, bool; `2` for vec2, ivec2, bvec2, etc.). The data type specified in the name of the command must match the data type for the specified uniform variable as described previously for $(REF uniform{1|2|3|4}{f|i|ui}).
	
	For uniform variable arrays, each element of the array is considered to be of the type indicated in the name of the command (e.g., $(REF uniform3f) or $(REF uniform3fv) can be used to load a uniform variable array of type vec3). The number of elements of the uniform variable array to be modified is specified by $(I `count`)
	
	The commands $(REF uniformMatrix{2|3|4|2x3|3x2|2x4|4x2|3x4|4x3}fv) are used to modify a matrix or an array of matrices. The numbers in the command name are interpreted as the dimensionality of the matrix. The number `2` indicates a 2 × 2 matrix (i.e., 4 values), the number `3` indicates a 3 × 3 matrix (i.e., 9 values), and the number `4` indicates a 4 × 4 matrix (i.e., 16 values). Non-square matrix dimensionality is explicit, with the first number representing the number of columns and the second number representing the number of rows. For example, `2x4` indicates a 2 × 4 matrix with 2 columns and 4 rows (i.e., 8 values). If $(I `transpose`) is `FALSE`, each matrix is assumed to be supplied in column major order. If $(I `transpose`) is `TRUE`, each matrix is assumed to be supplied in row major order. The $(I `count`) argument indicates the number of matrices to be passed. A count of 1 should be used if modifying the value of a single matrix, and a count greater than 1 can be used to modify an array of matrices.
	
	Params:
	location = Specifies the location of the uniform variable to be modified.
	count = For the vector ($(REF uniform*v)) commands, specifies the number of elements that are to be modified. This should be 1 if the targeted uniform variable is not an array, and 1 or more if it is an array. 
	
	 For the matrix ($(REF uniformMatrix*)) commands, specifies the number of matrices that are to be modified. This should be 1 if the targeted uniform variable is not an array of matrices, and 1 or more if it is an array of matrices.
	value = For the vector and matrix commands, specifies a pointer to an array of $(I `count`) values that will be used to update the specified uniform variable.
	*/
	void uniform1iv(Int location, Sizei count, const(Int)* value);
	
	/**
	$(REF uniform) modifies the value of a uniform variable or a uniform variable array. The location of the uniform variable to be modified is specified by $(I `location`), which should be a value returned by $(REF getUniformLocation). $(REF uniform) operates on the program object that was made part of current state by calling $(REF useProgram).
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}) are used to change the value of the uniform variable specified by $(I `location`) using the values passed as arguments. The number specified in the command should match the number of components in the data type of the specified uniform variable (e.g., `1` for `float`, `int`, `unsigned int`, `bool`; `2` for `vec2`, `ivec2`, `uvec2`, `bvec2`, etc.). The suffix `f` indicates that floating-point values are being passed; the suffix `i` indicates that integer values are being passed; the suffix `ui` indicates that unsigned integer values are being passed, and this type should also match the data type of the specified uniform variable. The `i` variants of this function should be used to provide values for uniform variables defined as `int`, `ivec2`, `ivec3`, `ivec4`, or arrays of these. The `ui` variants of this function should be used to provide values for uniform variables defined as `unsigned int`, `uvec2`, `uvec3`, `uvec4`, or arrays of these. The `f` variants should be used to provide values for uniform variables of type `float`, `vec2`, `vec3`, `vec4`, or arrays of these. Either the `i`, `ui` or `f` variants may be used to provide values for uniform variables of type `bool`, `bvec2`, `bvec3`, `bvec4`, or arrays of these. The uniform variable will be set to `false` if the input value is 0 or 0.0f, and it will be set to `true` otherwise.
	
	All active uniform variables defined in a program object are initialized to 0 when the program object is linked successfully. They retain the values assigned to them by a call to $(REF uniform ) until the next successful link operation occurs on the program object, when they are once again initialized to 0.
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}v) can be used to modify a single uniform variable or a uniform variable array. These commands pass a count and a pointer to the values to be loaded into a uniform variable or a uniform variable array. A count of 1 should be used if modifying the value of a single uniform variable, and a count of 1 or greater can be used to modify an entire array or part of an array. When loading $(I n) elements starting at an arbitrary position $(I m) in a uniform variable array, elements $(I m) + $(I n) - 1 in the array will be replaced with the new values. If $(I `m`) + $(I `n`) - 1 is larger than the size of the uniform variable array, values for all array elements beyond the end of the array will be ignored. The number specified in the name of the command indicates the number of components for each element in $(I `value`), and it should match the number of components in the data type of the specified uniform variable (e.g., `1` for float, int, bool; `2` for vec2, ivec2, bvec2, etc.). The data type specified in the name of the command must match the data type for the specified uniform variable as described previously for $(REF uniform{1|2|3|4}{f|i|ui}).
	
	For uniform variable arrays, each element of the array is considered to be of the type indicated in the name of the command (e.g., $(REF uniform3f) or $(REF uniform3fv) can be used to load a uniform variable array of type vec3). The number of elements of the uniform variable array to be modified is specified by $(I `count`)
	
	The commands $(REF uniformMatrix{2|3|4|2x3|3x2|2x4|4x2|3x4|4x3}fv) are used to modify a matrix or an array of matrices. The numbers in the command name are interpreted as the dimensionality of the matrix. The number `2` indicates a 2 × 2 matrix (i.e., 4 values), the number `3` indicates a 3 × 3 matrix (i.e., 9 values), and the number `4` indicates a 4 × 4 matrix (i.e., 16 values). Non-square matrix dimensionality is explicit, with the first number representing the number of columns and the second number representing the number of rows. For example, `2x4` indicates a 2 × 4 matrix with 2 columns and 4 rows (i.e., 8 values). If $(I `transpose`) is `FALSE`, each matrix is assumed to be supplied in column major order. If $(I `transpose`) is `TRUE`, each matrix is assumed to be supplied in row major order. The $(I `count`) argument indicates the number of matrices to be passed. A count of 1 should be used if modifying the value of a single matrix, and a count greater than 1 can be used to modify an array of matrices.
	
	Params:
	location = Specifies the location of the uniform variable to be modified.
	count = For the vector ($(REF uniform*v)) commands, specifies the number of elements that are to be modified. This should be 1 if the targeted uniform variable is not an array, and 1 or more if it is an array. 
	
	 For the matrix ($(REF uniformMatrix*)) commands, specifies the number of matrices that are to be modified. This should be 1 if the targeted uniform variable is not an array of matrices, and 1 or more if it is an array of matrices.
	value = For the vector and matrix commands, specifies a pointer to an array of $(I `count`) values that will be used to update the specified uniform variable.
	*/
	void uniform2iv(Int location, Sizei count, const(Int)* value);
	
	/**
	$(REF uniform) modifies the value of a uniform variable or a uniform variable array. The location of the uniform variable to be modified is specified by $(I `location`), which should be a value returned by $(REF getUniformLocation). $(REF uniform) operates on the program object that was made part of current state by calling $(REF useProgram).
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}) are used to change the value of the uniform variable specified by $(I `location`) using the values passed as arguments. The number specified in the command should match the number of components in the data type of the specified uniform variable (e.g., `1` for `float`, `int`, `unsigned int`, `bool`; `2` for `vec2`, `ivec2`, `uvec2`, `bvec2`, etc.). The suffix `f` indicates that floating-point values are being passed; the suffix `i` indicates that integer values are being passed; the suffix `ui` indicates that unsigned integer values are being passed, and this type should also match the data type of the specified uniform variable. The `i` variants of this function should be used to provide values for uniform variables defined as `int`, `ivec2`, `ivec3`, `ivec4`, or arrays of these. The `ui` variants of this function should be used to provide values for uniform variables defined as `unsigned int`, `uvec2`, `uvec3`, `uvec4`, or arrays of these. The `f` variants should be used to provide values for uniform variables of type `float`, `vec2`, `vec3`, `vec4`, or arrays of these. Either the `i`, `ui` or `f` variants may be used to provide values for uniform variables of type `bool`, `bvec2`, `bvec3`, `bvec4`, or arrays of these. The uniform variable will be set to `false` if the input value is 0 or 0.0f, and it will be set to `true` otherwise.
	
	All active uniform variables defined in a program object are initialized to 0 when the program object is linked successfully. They retain the values assigned to them by a call to $(REF uniform ) until the next successful link operation occurs on the program object, when they are once again initialized to 0.
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}v) can be used to modify a single uniform variable or a uniform variable array. These commands pass a count and a pointer to the values to be loaded into a uniform variable or a uniform variable array. A count of 1 should be used if modifying the value of a single uniform variable, and a count of 1 or greater can be used to modify an entire array or part of an array. When loading $(I n) elements starting at an arbitrary position $(I m) in a uniform variable array, elements $(I m) + $(I n) - 1 in the array will be replaced with the new values. If $(I `m`) + $(I `n`) - 1 is larger than the size of the uniform variable array, values for all array elements beyond the end of the array will be ignored. The number specified in the name of the command indicates the number of components for each element in $(I `value`), and it should match the number of components in the data type of the specified uniform variable (e.g., `1` for float, int, bool; `2` for vec2, ivec2, bvec2, etc.). The data type specified in the name of the command must match the data type for the specified uniform variable as described previously for $(REF uniform{1|2|3|4}{f|i|ui}).
	
	For uniform variable arrays, each element of the array is considered to be of the type indicated in the name of the command (e.g., $(REF uniform3f) or $(REF uniform3fv) can be used to load a uniform variable array of type vec3). The number of elements of the uniform variable array to be modified is specified by $(I `count`)
	
	The commands $(REF uniformMatrix{2|3|4|2x3|3x2|2x4|4x2|3x4|4x3}fv) are used to modify a matrix or an array of matrices. The numbers in the command name are interpreted as the dimensionality of the matrix. The number `2` indicates a 2 × 2 matrix (i.e., 4 values), the number `3` indicates a 3 × 3 matrix (i.e., 9 values), and the number `4` indicates a 4 × 4 matrix (i.e., 16 values). Non-square matrix dimensionality is explicit, with the first number representing the number of columns and the second number representing the number of rows. For example, `2x4` indicates a 2 × 4 matrix with 2 columns and 4 rows (i.e., 8 values). If $(I `transpose`) is `FALSE`, each matrix is assumed to be supplied in column major order. If $(I `transpose`) is `TRUE`, each matrix is assumed to be supplied in row major order. The $(I `count`) argument indicates the number of matrices to be passed. A count of 1 should be used if modifying the value of a single matrix, and a count greater than 1 can be used to modify an array of matrices.
	
	Params:
	location = Specifies the location of the uniform variable to be modified.
	count = For the vector ($(REF uniform*v)) commands, specifies the number of elements that are to be modified. This should be 1 if the targeted uniform variable is not an array, and 1 or more if it is an array. 
	
	 For the matrix ($(REF uniformMatrix*)) commands, specifies the number of matrices that are to be modified. This should be 1 if the targeted uniform variable is not an array of matrices, and 1 or more if it is an array of matrices.
	value = For the vector and matrix commands, specifies a pointer to an array of $(I `count`) values that will be used to update the specified uniform variable.
	*/
	void uniform3iv(Int location, Sizei count, const(Int)* value);
	
	/**
	$(REF uniform) modifies the value of a uniform variable or a uniform variable array. The location of the uniform variable to be modified is specified by $(I `location`), which should be a value returned by $(REF getUniformLocation). $(REF uniform) operates on the program object that was made part of current state by calling $(REF useProgram).
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}) are used to change the value of the uniform variable specified by $(I `location`) using the values passed as arguments. The number specified in the command should match the number of components in the data type of the specified uniform variable (e.g., `1` for `float`, `int`, `unsigned int`, `bool`; `2` for `vec2`, `ivec2`, `uvec2`, `bvec2`, etc.). The suffix `f` indicates that floating-point values are being passed; the suffix `i` indicates that integer values are being passed; the suffix `ui` indicates that unsigned integer values are being passed, and this type should also match the data type of the specified uniform variable. The `i` variants of this function should be used to provide values for uniform variables defined as `int`, `ivec2`, `ivec3`, `ivec4`, or arrays of these. The `ui` variants of this function should be used to provide values for uniform variables defined as `unsigned int`, `uvec2`, `uvec3`, `uvec4`, or arrays of these. The `f` variants should be used to provide values for uniform variables of type `float`, `vec2`, `vec3`, `vec4`, or arrays of these. Either the `i`, `ui` or `f` variants may be used to provide values for uniform variables of type `bool`, `bvec2`, `bvec3`, `bvec4`, or arrays of these. The uniform variable will be set to `false` if the input value is 0 or 0.0f, and it will be set to `true` otherwise.
	
	All active uniform variables defined in a program object are initialized to 0 when the program object is linked successfully. They retain the values assigned to them by a call to $(REF uniform ) until the next successful link operation occurs on the program object, when they are once again initialized to 0.
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}v) can be used to modify a single uniform variable or a uniform variable array. These commands pass a count and a pointer to the values to be loaded into a uniform variable or a uniform variable array. A count of 1 should be used if modifying the value of a single uniform variable, and a count of 1 or greater can be used to modify an entire array or part of an array. When loading $(I n) elements starting at an arbitrary position $(I m) in a uniform variable array, elements $(I m) + $(I n) - 1 in the array will be replaced with the new values. If $(I `m`) + $(I `n`) - 1 is larger than the size of the uniform variable array, values for all array elements beyond the end of the array will be ignored. The number specified in the name of the command indicates the number of components for each element in $(I `value`), and it should match the number of components in the data type of the specified uniform variable (e.g., `1` for float, int, bool; `2` for vec2, ivec2, bvec2, etc.). The data type specified in the name of the command must match the data type for the specified uniform variable as described previously for $(REF uniform{1|2|3|4}{f|i|ui}).
	
	For uniform variable arrays, each element of the array is considered to be of the type indicated in the name of the command (e.g., $(REF uniform3f) or $(REF uniform3fv) can be used to load a uniform variable array of type vec3). The number of elements of the uniform variable array to be modified is specified by $(I `count`)
	
	The commands $(REF uniformMatrix{2|3|4|2x3|3x2|2x4|4x2|3x4|4x3}fv) are used to modify a matrix or an array of matrices. The numbers in the command name are interpreted as the dimensionality of the matrix. The number `2` indicates a 2 × 2 matrix (i.e., 4 values), the number `3` indicates a 3 × 3 matrix (i.e., 9 values), and the number `4` indicates a 4 × 4 matrix (i.e., 16 values). Non-square matrix dimensionality is explicit, with the first number representing the number of columns and the second number representing the number of rows. For example, `2x4` indicates a 2 × 4 matrix with 2 columns and 4 rows (i.e., 8 values). If $(I `transpose`) is `FALSE`, each matrix is assumed to be supplied in column major order. If $(I `transpose`) is `TRUE`, each matrix is assumed to be supplied in row major order. The $(I `count`) argument indicates the number of matrices to be passed. A count of 1 should be used if modifying the value of a single matrix, and a count greater than 1 can be used to modify an array of matrices.
	
	Params:
	location = Specifies the location of the uniform variable to be modified.
	count = For the vector ($(REF uniform*v)) commands, specifies the number of elements that are to be modified. This should be 1 if the targeted uniform variable is not an array, and 1 or more if it is an array. 
	
	 For the matrix ($(REF uniformMatrix*)) commands, specifies the number of matrices that are to be modified. This should be 1 if the targeted uniform variable is not an array of matrices, and 1 or more if it is an array of matrices.
	value = For the vector and matrix commands, specifies a pointer to an array of $(I `count`) values that will be used to update the specified uniform variable.
	*/
	void uniform4iv(Int location, Sizei count, const(Int)* value);
	
	/**
	$(REF uniform) modifies the value of a uniform variable or a uniform variable array. The location of the uniform variable to be modified is specified by $(I `location`), which should be a value returned by $(REF getUniformLocation). $(REF uniform) operates on the program object that was made part of current state by calling $(REF useProgram).
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}) are used to change the value of the uniform variable specified by $(I `location`) using the values passed as arguments. The number specified in the command should match the number of components in the data type of the specified uniform variable (e.g., `1` for `float`, `int`, `unsigned int`, `bool`; `2` for `vec2`, `ivec2`, `uvec2`, `bvec2`, etc.). The suffix `f` indicates that floating-point values are being passed; the suffix `i` indicates that integer values are being passed; the suffix `ui` indicates that unsigned integer values are being passed, and this type should also match the data type of the specified uniform variable. The `i` variants of this function should be used to provide values for uniform variables defined as `int`, `ivec2`, `ivec3`, `ivec4`, or arrays of these. The `ui` variants of this function should be used to provide values for uniform variables defined as `unsigned int`, `uvec2`, `uvec3`, `uvec4`, or arrays of these. The `f` variants should be used to provide values for uniform variables of type `float`, `vec2`, `vec3`, `vec4`, or arrays of these. Either the `i`, `ui` or `f` variants may be used to provide values for uniform variables of type `bool`, `bvec2`, `bvec3`, `bvec4`, or arrays of these. The uniform variable will be set to `false` if the input value is 0 or 0.0f, and it will be set to `true` otherwise.
	
	All active uniform variables defined in a program object are initialized to 0 when the program object is linked successfully. They retain the values assigned to them by a call to $(REF uniform ) until the next successful link operation occurs on the program object, when they are once again initialized to 0.
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}v) can be used to modify a single uniform variable or a uniform variable array. These commands pass a count and a pointer to the values to be loaded into a uniform variable or a uniform variable array. A count of 1 should be used if modifying the value of a single uniform variable, and a count of 1 or greater can be used to modify an entire array or part of an array. When loading $(I n) elements starting at an arbitrary position $(I m) in a uniform variable array, elements $(I m) + $(I n) - 1 in the array will be replaced with the new values. If $(I `m`) + $(I `n`) - 1 is larger than the size of the uniform variable array, values for all array elements beyond the end of the array will be ignored. The number specified in the name of the command indicates the number of components for each element in $(I `value`), and it should match the number of components in the data type of the specified uniform variable (e.g., `1` for float, int, bool; `2` for vec2, ivec2, bvec2, etc.). The data type specified in the name of the command must match the data type for the specified uniform variable as described previously for $(REF uniform{1|2|3|4}{f|i|ui}).
	
	For uniform variable arrays, each element of the array is considered to be of the type indicated in the name of the command (e.g., $(REF uniform3f) or $(REF uniform3fv) can be used to load a uniform variable array of type vec3). The number of elements of the uniform variable array to be modified is specified by $(I `count`)
	
	The commands $(REF uniformMatrix{2|3|4|2x3|3x2|2x4|4x2|3x4|4x3}fv) are used to modify a matrix or an array of matrices. The numbers in the command name are interpreted as the dimensionality of the matrix. The number `2` indicates a 2 × 2 matrix (i.e., 4 values), the number `3` indicates a 3 × 3 matrix (i.e., 9 values), and the number `4` indicates a 4 × 4 matrix (i.e., 16 values). Non-square matrix dimensionality is explicit, with the first number representing the number of columns and the second number representing the number of rows. For example, `2x4` indicates a 2 × 4 matrix with 2 columns and 4 rows (i.e., 8 values). If $(I `transpose`) is `FALSE`, each matrix is assumed to be supplied in column major order. If $(I `transpose`) is `TRUE`, each matrix is assumed to be supplied in row major order. The $(I `count`) argument indicates the number of matrices to be passed. A count of 1 should be used if modifying the value of a single matrix, and a count greater than 1 can be used to modify an array of matrices.
	
	Params:
	location = Specifies the location of the uniform variable to be modified.
	count = For the vector ($(REF uniform*v)) commands, specifies the number of elements that are to be modified. This should be 1 if the targeted uniform variable is not an array, and 1 or more if it is an array. 
	
	 For the matrix ($(REF uniformMatrix*)) commands, specifies the number of matrices that are to be modified. This should be 1 if the targeted uniform variable is not an array of matrices, and 1 or more if it is an array of matrices.
	transpose = For the matrix commands, specifies whether to transpose the matrix as the values are loaded into the uniform variable.
	value = For the vector and matrix commands, specifies a pointer to an array of $(I `count`) values that will be used to update the specified uniform variable.
	*/
	void uniformMatrix2fv(Int location, Sizei count, Boolean transpose, const(Float)* value);
	
	/**
	$(REF uniform) modifies the value of a uniform variable or a uniform variable array. The location of the uniform variable to be modified is specified by $(I `location`), which should be a value returned by $(REF getUniformLocation). $(REF uniform) operates on the program object that was made part of current state by calling $(REF useProgram).
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}) are used to change the value of the uniform variable specified by $(I `location`) using the values passed as arguments. The number specified in the command should match the number of components in the data type of the specified uniform variable (e.g., `1` for `float`, `int`, `unsigned int`, `bool`; `2` for `vec2`, `ivec2`, `uvec2`, `bvec2`, etc.). The suffix `f` indicates that floating-point values are being passed; the suffix `i` indicates that integer values are being passed; the suffix `ui` indicates that unsigned integer values are being passed, and this type should also match the data type of the specified uniform variable. The `i` variants of this function should be used to provide values for uniform variables defined as `int`, `ivec2`, `ivec3`, `ivec4`, or arrays of these. The `ui` variants of this function should be used to provide values for uniform variables defined as `unsigned int`, `uvec2`, `uvec3`, `uvec4`, or arrays of these. The `f` variants should be used to provide values for uniform variables of type `float`, `vec2`, `vec3`, `vec4`, or arrays of these. Either the `i`, `ui` or `f` variants may be used to provide values for uniform variables of type `bool`, `bvec2`, `bvec3`, `bvec4`, or arrays of these. The uniform variable will be set to `false` if the input value is 0 or 0.0f, and it will be set to `true` otherwise.
	
	All active uniform variables defined in a program object are initialized to 0 when the program object is linked successfully. They retain the values assigned to them by a call to $(REF uniform ) until the next successful link operation occurs on the program object, when they are once again initialized to 0.
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}v) can be used to modify a single uniform variable or a uniform variable array. These commands pass a count and a pointer to the values to be loaded into a uniform variable or a uniform variable array. A count of 1 should be used if modifying the value of a single uniform variable, and a count of 1 or greater can be used to modify an entire array or part of an array. When loading $(I n) elements starting at an arbitrary position $(I m) in a uniform variable array, elements $(I m) + $(I n) - 1 in the array will be replaced with the new values. If $(I `m`) + $(I `n`) - 1 is larger than the size of the uniform variable array, values for all array elements beyond the end of the array will be ignored. The number specified in the name of the command indicates the number of components for each element in $(I `value`), and it should match the number of components in the data type of the specified uniform variable (e.g., `1` for float, int, bool; `2` for vec2, ivec2, bvec2, etc.). The data type specified in the name of the command must match the data type for the specified uniform variable as described previously for $(REF uniform{1|2|3|4}{f|i|ui}).
	
	For uniform variable arrays, each element of the array is considered to be of the type indicated in the name of the command (e.g., $(REF uniform3f) or $(REF uniform3fv) can be used to load a uniform variable array of type vec3). The number of elements of the uniform variable array to be modified is specified by $(I `count`)
	
	The commands $(REF uniformMatrix{2|3|4|2x3|3x2|2x4|4x2|3x4|4x3}fv) are used to modify a matrix or an array of matrices. The numbers in the command name are interpreted as the dimensionality of the matrix. The number `2` indicates a 2 × 2 matrix (i.e., 4 values), the number `3` indicates a 3 × 3 matrix (i.e., 9 values), and the number `4` indicates a 4 × 4 matrix (i.e., 16 values). Non-square matrix dimensionality is explicit, with the first number representing the number of columns and the second number representing the number of rows. For example, `2x4` indicates a 2 × 4 matrix with 2 columns and 4 rows (i.e., 8 values). If $(I `transpose`) is `FALSE`, each matrix is assumed to be supplied in column major order. If $(I `transpose`) is `TRUE`, each matrix is assumed to be supplied in row major order. The $(I `count`) argument indicates the number of matrices to be passed. A count of 1 should be used if modifying the value of a single matrix, and a count greater than 1 can be used to modify an array of matrices.
	
	Params:
	location = Specifies the location of the uniform variable to be modified.
	count = For the vector ($(REF uniform*v)) commands, specifies the number of elements that are to be modified. This should be 1 if the targeted uniform variable is not an array, and 1 or more if it is an array. 
	
	 For the matrix ($(REF uniformMatrix*)) commands, specifies the number of matrices that are to be modified. This should be 1 if the targeted uniform variable is not an array of matrices, and 1 or more if it is an array of matrices.
	transpose = For the matrix commands, specifies whether to transpose the matrix as the values are loaded into the uniform variable.
	value = For the vector and matrix commands, specifies a pointer to an array of $(I `count`) values that will be used to update the specified uniform variable.
	*/
	void uniformMatrix3fv(Int location, Sizei count, Boolean transpose, const(Float)* value);
	
	/**
	$(REF uniform) modifies the value of a uniform variable or a uniform variable array. The location of the uniform variable to be modified is specified by $(I `location`), which should be a value returned by $(REF getUniformLocation). $(REF uniform) operates on the program object that was made part of current state by calling $(REF useProgram).
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}) are used to change the value of the uniform variable specified by $(I `location`) using the values passed as arguments. The number specified in the command should match the number of components in the data type of the specified uniform variable (e.g., `1` for `float`, `int`, `unsigned int`, `bool`; `2` for `vec2`, `ivec2`, `uvec2`, `bvec2`, etc.). The suffix `f` indicates that floating-point values are being passed; the suffix `i` indicates that integer values are being passed; the suffix `ui` indicates that unsigned integer values are being passed, and this type should also match the data type of the specified uniform variable. The `i` variants of this function should be used to provide values for uniform variables defined as `int`, `ivec2`, `ivec3`, `ivec4`, or arrays of these. The `ui` variants of this function should be used to provide values for uniform variables defined as `unsigned int`, `uvec2`, `uvec3`, `uvec4`, or arrays of these. The `f` variants should be used to provide values for uniform variables of type `float`, `vec2`, `vec3`, `vec4`, or arrays of these. Either the `i`, `ui` or `f` variants may be used to provide values for uniform variables of type `bool`, `bvec2`, `bvec3`, `bvec4`, or arrays of these. The uniform variable will be set to `false` if the input value is 0 or 0.0f, and it will be set to `true` otherwise.
	
	All active uniform variables defined in a program object are initialized to 0 when the program object is linked successfully. They retain the values assigned to them by a call to $(REF uniform ) until the next successful link operation occurs on the program object, when they are once again initialized to 0.
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}v) can be used to modify a single uniform variable or a uniform variable array. These commands pass a count and a pointer to the values to be loaded into a uniform variable or a uniform variable array. A count of 1 should be used if modifying the value of a single uniform variable, and a count of 1 or greater can be used to modify an entire array or part of an array. When loading $(I n) elements starting at an arbitrary position $(I m) in a uniform variable array, elements $(I m) + $(I n) - 1 in the array will be replaced with the new values. If $(I `m`) + $(I `n`) - 1 is larger than the size of the uniform variable array, values for all array elements beyond the end of the array will be ignored. The number specified in the name of the command indicates the number of components for each element in $(I `value`), and it should match the number of components in the data type of the specified uniform variable (e.g., `1` for float, int, bool; `2` for vec2, ivec2, bvec2, etc.). The data type specified in the name of the command must match the data type for the specified uniform variable as described previously for $(REF uniform{1|2|3|4}{f|i|ui}).
	
	For uniform variable arrays, each element of the array is considered to be of the type indicated in the name of the command (e.g., $(REF uniform3f) or $(REF uniform3fv) can be used to load a uniform variable array of type vec3). The number of elements of the uniform variable array to be modified is specified by $(I `count`)
	
	The commands $(REF uniformMatrix{2|3|4|2x3|3x2|2x4|4x2|3x4|4x3}fv) are used to modify a matrix or an array of matrices. The numbers in the command name are interpreted as the dimensionality of the matrix. The number `2` indicates a 2 × 2 matrix (i.e., 4 values), the number `3` indicates a 3 × 3 matrix (i.e., 9 values), and the number `4` indicates a 4 × 4 matrix (i.e., 16 values). Non-square matrix dimensionality is explicit, with the first number representing the number of columns and the second number representing the number of rows. For example, `2x4` indicates a 2 × 4 matrix with 2 columns and 4 rows (i.e., 8 values). If $(I `transpose`) is `FALSE`, each matrix is assumed to be supplied in column major order. If $(I `transpose`) is `TRUE`, each matrix is assumed to be supplied in row major order. The $(I `count`) argument indicates the number of matrices to be passed. A count of 1 should be used if modifying the value of a single matrix, and a count greater than 1 can be used to modify an array of matrices.
	
	Params:
	location = Specifies the location of the uniform variable to be modified.
	count = For the vector ($(REF uniform*v)) commands, specifies the number of elements that are to be modified. This should be 1 if the targeted uniform variable is not an array, and 1 or more if it is an array. 
	
	 For the matrix ($(REF uniformMatrix*)) commands, specifies the number of matrices that are to be modified. This should be 1 if the targeted uniform variable is not an array of matrices, and 1 or more if it is an array of matrices.
	transpose = For the matrix commands, specifies whether to transpose the matrix as the values are loaded into the uniform variable.
	value = For the vector and matrix commands, specifies a pointer to an array of $(I `count`) values that will be used to update the specified uniform variable.
	*/
	void uniformMatrix4fv(Int location, Sizei count, Boolean transpose, const(Float)* value);
	
	/**
	$(REF validateProgram) checks to see whether the executables contained in $(I `program`) can execute given the current OpenGL state. The information generated by the validation process will be stored in $(I `program`)'s information log. The validation information may consist of an empty string, or it may be a string containing information about how the current program object interacts with the rest of current OpenGL state. This provides a way for OpenGL implementers to convey more information about why the current program is inefficient, suboptimal, failing to execute, and so on.
	
	The status of the validation operation will be stored as part of the program object's state. This value will be set to `TRUE` if the validation succeeded, and `FALSE` otherwise. It can be queried by calling $(REF getProgram) with arguments $(I `program`) and `VALIDATE_STATUS`. If validation is successful, $(I `program`) is guaranteed to execute given the current state. Otherwise, $(I `program`) is guaranteed to not execute.
	
	This function is typically useful only during application development. The informational string stored in the information log is completely implementation dependent; therefore, an application should not expect different OpenGL implementations to produce identical information strings.
	
	Params:
	program = Specifies the handle of the program object to be validated.
	*/
	void validateProgram(UInt program);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v0 = For the scalar commands, specifies the new values to be used for the specified vertex attribute.
	*/
	void vertexAttrib1d(UInt index, Double v0);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v = For the vector commands ($(REF vertexAttrib*v)), specifies a pointer to an array of values to be used for the generic vertex attribute.
	*/
	void vertexAttrib1dv(UInt index, const(Double)* v);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v0 = For the scalar commands, specifies the new values to be used for the specified vertex attribute.
	*/
	void vertexAttrib1f(UInt index, Float v0);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v = For the vector commands ($(REF vertexAttrib*v)), specifies a pointer to an array of values to be used for the generic vertex attribute.
	*/
	void vertexAttrib1fv(UInt index, const(Float)* v);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v0 = For the scalar commands, specifies the new values to be used for the specified vertex attribute.
	*/
	void vertexAttrib1s(UInt index, Short v0);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v = For the vector commands ($(REF vertexAttrib*v)), specifies a pointer to an array of values to be used for the generic vertex attribute.
	*/
	void vertexAttrib1sv(UInt index, const(Short)* v);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v0 = For the scalar commands, specifies the new values to be used for the specified vertex attribute.
	v1 = For the scalar commands, specifies the new values to be used for the specified vertex attribute.
	*/
	void vertexAttrib2d(UInt index, Double v0, Double v1);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v = For the vector commands ($(REF vertexAttrib*v)), specifies a pointer to an array of values to be used for the generic vertex attribute.
	*/
	void vertexAttrib2dv(UInt index, const(Double)* v);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v0 = For the scalar commands, specifies the new values to be used for the specified vertex attribute.
	v1 = For the scalar commands, specifies the new values to be used for the specified vertex attribute.
	*/
	void vertexAttrib2f(UInt index, Float v0, Float v1);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v = For the vector commands ($(REF vertexAttrib*v)), specifies a pointer to an array of values to be used for the generic vertex attribute.
	*/
	void vertexAttrib2fv(UInt index, const(Float)* v);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v0 = For the scalar commands, specifies the new values to be used for the specified vertex attribute.
	v1 = For the scalar commands, specifies the new values to be used for the specified vertex attribute.
	*/
	void vertexAttrib2s(UInt index, Short v0, Short v1);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v = For the vector commands ($(REF vertexAttrib*v)), specifies a pointer to an array of values to be used for the generic vertex attribute.
	*/
	void vertexAttrib2sv(UInt index, const(Short)* v);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v0 = For the scalar commands, specifies the new values to be used for the specified vertex attribute.
	v1 = For the scalar commands, specifies the new values to be used for the specified vertex attribute.
	v2 = For the scalar commands, specifies the new values to be used for the specified vertex attribute.
	*/
	void vertexAttrib3d(UInt index, Double v0, Double v1, Double v2);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v = For the vector commands ($(REF vertexAttrib*v)), specifies a pointer to an array of values to be used for the generic vertex attribute.
	*/
	void vertexAttrib3dv(UInt index, const(Double)* v);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v0 = For the scalar commands, specifies the new values to be used for the specified vertex attribute.
	v1 = For the scalar commands, specifies the new values to be used for the specified vertex attribute.
	v2 = For the scalar commands, specifies the new values to be used for the specified vertex attribute.
	*/
	void vertexAttrib3f(UInt index, Float v0, Float v1, Float v2);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v = For the vector commands ($(REF vertexAttrib*v)), specifies a pointer to an array of values to be used for the generic vertex attribute.
	*/
	void vertexAttrib3fv(UInt index, const(Float)* v);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v0 = For the scalar commands, specifies the new values to be used for the specified vertex attribute.
	v1 = For the scalar commands, specifies the new values to be used for the specified vertex attribute.
	v2 = For the scalar commands, specifies the new values to be used for the specified vertex attribute.
	*/
	void vertexAttrib3s(UInt index, Short v0, Short v1, Short v2);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v = For the vector commands ($(REF vertexAttrib*v)), specifies a pointer to an array of values to be used for the generic vertex attribute.
	*/
	void vertexAttrib3sv(UInt index, const(Short)* v);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v = For the vector commands ($(REF vertexAttrib*v)), specifies a pointer to an array of values to be used for the generic vertex attribute.
	*/
	void vertexAttrib4Nbv(UInt index, const(Byte)* v);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v = For the vector commands ($(REF vertexAttrib*v)), specifies a pointer to an array of values to be used for the generic vertex attribute.
	*/
	void vertexAttrib4Niv(UInt index, const(Int)* v);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v = For the vector commands ($(REF vertexAttrib*v)), specifies a pointer to an array of values to be used for the generic vertex attribute.
	*/
	void vertexAttrib4Nsv(UInt index, const(Short)* v);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v0 = For the scalar commands, specifies the new values to be used for the specified vertex attribute.
	v1 = For the scalar commands, specifies the new values to be used for the specified vertex attribute.
	v2 = For the scalar commands, specifies the new values to be used for the specified vertex attribute.
	v3 = For the scalar commands, specifies the new values to be used for the specified vertex attribute.
	*/
	void vertexAttrib4Nub(UInt index, UByte v0, UByte v1, UByte v2, UByte v3);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v = For the vector commands ($(REF vertexAttrib*v)), specifies a pointer to an array of values to be used for the generic vertex attribute.
	*/
	void vertexAttrib4Nubv(UInt index, const(UByte)* v);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v = For the vector commands ($(REF vertexAttrib*v)), specifies a pointer to an array of values to be used for the generic vertex attribute.
	*/
	void vertexAttrib4Nuiv(UInt index, const(UInt)* v);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v = For the vector commands ($(REF vertexAttrib*v)), specifies a pointer to an array of values to be used for the generic vertex attribute.
	*/
	void vertexAttrib4Nusv(UInt index, const(UShort)* v);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v = For the vector commands ($(REF vertexAttrib*v)), specifies a pointer to an array of values to be used for the generic vertex attribute.
	*/
	void vertexAttrib4bv(UInt index, const(Byte)* v);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v0 = For the scalar commands, specifies the new values to be used for the specified vertex attribute.
	v1 = For the scalar commands, specifies the new values to be used for the specified vertex attribute.
	v2 = For the scalar commands, specifies the new values to be used for the specified vertex attribute.
	v3 = For the scalar commands, specifies the new values to be used for the specified vertex attribute.
	*/
	void vertexAttrib4d(UInt index, Double v0, Double v1, Double v2, Double v3);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v = For the vector commands ($(REF vertexAttrib*v)), specifies a pointer to an array of values to be used for the generic vertex attribute.
	*/
	void vertexAttrib4dv(UInt index, const(Double)* v);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v0 = For the scalar commands, specifies the new values to be used for the specified vertex attribute.
	v1 = For the scalar commands, specifies the new values to be used for the specified vertex attribute.
	v2 = For the scalar commands, specifies the new values to be used for the specified vertex attribute.
	v3 = For the scalar commands, specifies the new values to be used for the specified vertex attribute.
	*/
	void vertexAttrib4f(UInt index, Float v0, Float v1, Float v2, Float v3);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v = For the vector commands ($(REF vertexAttrib*v)), specifies a pointer to an array of values to be used for the generic vertex attribute.
	*/
	void vertexAttrib4fv(UInt index, const(Float)* v);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v = For the vector commands ($(REF vertexAttrib*v)), specifies a pointer to an array of values to be used for the generic vertex attribute.
	*/
	void vertexAttrib4iv(UInt index, const(Int)* v);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v0 = For the scalar commands, specifies the new values to be used for the specified vertex attribute.
	v1 = For the scalar commands, specifies the new values to be used for the specified vertex attribute.
	v2 = For the scalar commands, specifies the new values to be used for the specified vertex attribute.
	v3 = For the scalar commands, specifies the new values to be used for the specified vertex attribute.
	*/
	void vertexAttrib4s(UInt index, Short v0, Short v1, Short v2, Short v3);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v = For the vector commands ($(REF vertexAttrib*v)), specifies a pointer to an array of values to be used for the generic vertex attribute.
	*/
	void vertexAttrib4sv(UInt index, const(Short)* v);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v = For the vector commands ($(REF vertexAttrib*v)), specifies a pointer to an array of values to be used for the generic vertex attribute.
	*/
	void vertexAttrib4ubv(UInt index, const(UByte)* v);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v = For the vector commands ($(REF vertexAttrib*v)), specifies a pointer to an array of values to be used for the generic vertex attribute.
	*/
	void vertexAttrib4uiv(UInt index, const(UInt)* v);
	
	/**
	The $(REF vertexAttrib) family of entry points allows an application to pass generic vertex attributes in numbered locations.
	
	Generic attributes are defined as four-component values that are organized into an array. The first entry of this array is numbered 0, and the size of the array is specified by the implementation-dependent constant `MAX_VERTEX_ATTRIBS`. Individual elements of this array can be modified with a $(REF vertexAttrib) call that specifies the index of the element to be modified and a value for that element.
	
	These commands can be used to specify one, two, three, or all four components of the generic vertex attribute specified by $(I `index`). A `1` in the name of the command indicates that only one value is passed, and it will be used to modify the first component of the generic vertex attribute. The second and third components will be set to 0, and the fourth component will be set to 1. Similarly, a `2` in the name of the command indicates that values are provided for the first two components, the third component will be set to 0, and the fourth component will be set to 1. A `3` in the name of the command indicates that values are provided for the first three components and the fourth component will be set to 1, whereas a `4` in the name indicates that values are provided for all four components.
	
	The letters `s`, `f`, `i`, `d`, `ub`, `us`, and `ui` indicate whether the arguments are of type short, float, int, double, unsigned byte, unsigned short, or unsigned int. When `v` is appended to the name, the commands can take a pointer to an array of such values.
	
	Additional capitalized letters can indicate further alterations to the default behavior of the glVertexAttrib function:
	
	The commands containing `N` indicate that the arguments will be passed as fixed-point values that are scaled to a normalized range according to the component conversion rules defined by the OpenGL specification. Signed values are understood to represent fixed-point values in the range [-1,1], and unsigned values are understood to represent fixed-point values in the range [0,1].
	
	The commands containing `I` indicate that the arguments are extended to full signed or unsigned integers.
	
	The commands containing `P` indicate that the arguments are stored as packed components within a larger natural type.
	
	The commands containing `L` indicate that the arguments are full 64-bit quantities and should be passed directly to shader inputs declared as 64-bit double precision types.
	
	OpenGL Shading Language attribute variables are allowed to be of type mat2, mat3, or mat4. Attributes of these types may be loaded using the $(REF vertexAttrib) entry points. Matrices must be loaded into successive generic attribute slots in column major order, with one column of the matrix in each generic attribute slot.
	
	A user-defined attribute variable declared in a vertex shader can be bound to a generic attribute index by calling $(REF bindAttribLocation). This allows an application to use more descriptive variable names in a vertex shader. A subsequent change to the specified generic vertex attribute will be immediately reflected as a change to the corresponding attribute variable in the vertex shader.
	
	The binding between a generic vertex attribute index and a user-defined attribute variable in a vertex shader is part of the state of a program object, but the current value of the generic vertex attribute is not. The value of each generic vertex attribute is part of current state, just like standard vertex attributes, and it is maintained even if a different program object is used.
	
	An application may freely modify generic vertex attributes that are not bound to a named vertex shader attribute variable. These values are simply maintained as part of current state and will not be accessed by the vertex shader. If a generic vertex attribute bound to an attribute variable in a vertex shader is not updated while the vertex shader is executing, the vertex shader will repeatedly use the current value for the generic vertex attribute.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	v = For the vector commands ($(REF vertexAttrib*v)), specifies a pointer to an array of values to be used for the generic vertex attribute.
	*/
	void vertexAttrib4usv(UInt index, const(UShort)* v);
	
	/**
	$(REF vertexAttribPointer), $(REF vertexAttribIPointer) and $(REF vertexAttribLPointer) specify the location and data format of the array of generic vertex attributes at index $(I `index`) to use when rendering. $(I `size`) specifies the number of components per attribute and must be 1, 2, 3, 4, or `BGRA`. $(I `type`) specifies the data type of each component, and $(I `stride`) specifies the byte stride from one attribute to the next, allowing vertices and attributes to be packed into a single array or stored in separate arrays.
	
	For $(REF vertexAttribPointer), if $(I `normalized`) is set to `TRUE`, it indicates that values stored in an integer format are to be mapped to the range [-1,1] (for signed values) or [0,1] (for unsigned values) when they are accessed and converted to floating point. Otherwise, values will be converted to floats directly without normalization.
	
	For $(REF vertexAttribIPointer), only the integer types `BYTE`, `UNSIGNED_BYTE`, `SHORT`, `UNSIGNED_SHORT`, `INT`, `UNSIGNED_INT` are accepted. Values are always left as integer values.
	
	$(REF vertexAttribLPointer) specifies state for a generic vertex attribute array associated with a shader attribute variable declared with 64-bit double precision components. $(I `type`) must be `DOUBLE`. $(I `index`), $(I `size`), and $(I `stride`) behave as described for $(REF vertexAttribPointer) and $(REF vertexAttribIPointer).
	
	If $(I `pointer`) is not `NULL`, a non-zero named buffer object must be bound to the `ARRAY_BUFFER` target (see $(REF bindBuffer)), otherwise an error is generated. $(I `pointer`) is treated as a byte offset into the buffer object's data store. The buffer object binding (`ARRAY_BUFFER_BINDING`) is saved as generic vertex attribute array state (`VERTEX_ATTRIB_ARRAY_BUFFER_BINDING`) for index $(I `index`).
	
	When a generic vertex attribute array is specified, $(I `size`), $(I `type`), $(I `normalized`), $(I `stride`), and $(I `pointer`) are saved as vertex array state, in addition to the current vertex array buffer object binding.
	
	To enable and disable a generic vertex attribute array, call $(REF enableVertexAttribArray) and $(REF disableVertexAttribArray) with $(I `index`). If enabled, the generic vertex attribute array is used when $(REF drawArrays), $(REF multiDrawArrays), $(REF drawElements), $(REF multiDrawElements), or $(REF drawRangeElements) is called.
	
	Params:
	index = Specifies the index of the generic vertex attribute to be modified.
	size = Specifies the number of components per generic vertex attribute. Must be 1, 2, 3, 4. Additionally, the symbolic constant `BGRA` is accepted by $(REF vertexAttribPointer). The initial value is 4.
	type = Specifies the data type of each component in the array. The symbolic constants `BYTE`, `UNSIGNED_BYTE`, `SHORT`, `UNSIGNED_SHORT`, `INT`, and `UNSIGNED_INT` are accepted by $(REF vertexAttribPointer) and $(REF vertexAttribIPointer). Additionally `HALF_FLOAT`, `FLOAT`, `DOUBLE`, `FIXED`, `INT_2_10_10_10_REV`, `UNSIGNED_INT_2_10_10_10_REV` and `UNSIGNED_INT_10F_11F_11F_REV` are accepted by $(REF vertexAttribPointer). `DOUBLE` is also accepted by $(REF vertexAttribLPointer) and is the only token accepted by the $(I `type`) parameter for that function. The initial value is `FLOAT`.
	normalized = For $(REF vertexAttribPointer), specifies whether fixed-point data values should be normalized (`TRUE`) or converted directly as fixed-point values (`FALSE`) when they are accessed.
	stride = Specifies the byte offset between consecutive generic vertex attributes. If $(I `stride`) is 0, the generic vertex attributes are understood to be tightly packed in the array. The initial value is 0.
	pointer = Specifies a offset of the first component of the first generic vertex attribute in the array in the data store of the buffer currently bound to the `ARRAY_BUFFER` target. The initial value is 0.
	*/
	void vertexAttribPointer(UInt index, Int size, Enum type, Boolean normalized, Sizei stride, const(void)* pointer);
	
	/**
	$(REF uniform) modifies the value of a uniform variable or a uniform variable array. The location of the uniform variable to be modified is specified by $(I `location`), which should be a value returned by $(REF getUniformLocation). $(REF uniform) operates on the program object that was made part of current state by calling $(REF useProgram).
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}) are used to change the value of the uniform variable specified by $(I `location`) using the values passed as arguments. The number specified in the command should match the number of components in the data type of the specified uniform variable (e.g., `1` for `float`, `int`, `unsigned int`, `bool`; `2` for `vec2`, `ivec2`, `uvec2`, `bvec2`, etc.). The suffix `f` indicates that floating-point values are being passed; the suffix `i` indicates that integer values are being passed; the suffix `ui` indicates that unsigned integer values are being passed, and this type should also match the data type of the specified uniform variable. The `i` variants of this function should be used to provide values for uniform variables defined as `int`, `ivec2`, `ivec3`, `ivec4`, or arrays of these. The `ui` variants of this function should be used to provide values for uniform variables defined as `unsigned int`, `uvec2`, `uvec3`, `uvec4`, or arrays of these. The `f` variants should be used to provide values for uniform variables of type `float`, `vec2`, `vec3`, `vec4`, or arrays of these. Either the `i`, `ui` or `f` variants may be used to provide values for uniform variables of type `bool`, `bvec2`, `bvec3`, `bvec4`, or arrays of these. The uniform variable will be set to `false` if the input value is 0 or 0.0f, and it will be set to `true` otherwise.
	
	All active uniform variables defined in a program object are initialized to 0 when the program object is linked successfully. They retain the values assigned to them by a call to $(REF uniform ) until the next successful link operation occurs on the program object, when they are once again initialized to 0.
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}v) can be used to modify a single uniform variable or a uniform variable array. These commands pass a count and a pointer to the values to be loaded into a uniform variable or a uniform variable array. A count of 1 should be used if modifying the value of a single uniform variable, and a count of 1 or greater can be used to modify an entire array or part of an array. When loading $(I n) elements starting at an arbitrary position $(I m) in a uniform variable array, elements $(I m) + $(I n) - 1 in the array will be replaced with the new values. If $(I `m`) + $(I `n`) - 1 is larger than the size of the uniform variable array, values for all array elements beyond the end of the array will be ignored. The number specified in the name of the command indicates the number of components for each element in $(I `value`), and it should match the number of components in the data type of the specified uniform variable (e.g., `1` for float, int, bool; `2` for vec2, ivec2, bvec2, etc.). The data type specified in the name of the command must match the data type for the specified uniform variable as described previously for $(REF uniform{1|2|3|4}{f|i|ui}).
	
	For uniform variable arrays, each element of the array is considered to be of the type indicated in the name of the command (e.g., $(REF uniform3f) or $(REF uniform3fv) can be used to load a uniform variable array of type vec3). The number of elements of the uniform variable array to be modified is specified by $(I `count`)
	
	The commands $(REF uniformMatrix{2|3|4|2x3|3x2|2x4|4x2|3x4|4x3}fv) are used to modify a matrix or an array of matrices. The numbers in the command name are interpreted as the dimensionality of the matrix. The number `2` indicates a 2 × 2 matrix (i.e., 4 values), the number `3` indicates a 3 × 3 matrix (i.e., 9 values), and the number `4` indicates a 4 × 4 matrix (i.e., 16 values). Non-square matrix dimensionality is explicit, with the first number representing the number of columns and the second number representing the number of rows. For example, `2x4` indicates a 2 × 4 matrix with 2 columns and 4 rows (i.e., 8 values). If $(I `transpose`) is `FALSE`, each matrix is assumed to be supplied in column major order. If $(I `transpose`) is `TRUE`, each matrix is assumed to be supplied in row major order. The $(I `count`) argument indicates the number of matrices to be passed. A count of 1 should be used if modifying the value of a single matrix, and a count greater than 1 can be used to modify an array of matrices.
	
	Params:
	location = Specifies the location of the uniform variable to be modified.
	count = For the vector ($(REF uniform*v)) commands, specifies the number of elements that are to be modified. This should be 1 if the targeted uniform variable is not an array, and 1 or more if it is an array. 
	
	 For the matrix ($(REF uniformMatrix*)) commands, specifies the number of matrices that are to be modified. This should be 1 if the targeted uniform variable is not an array of matrices, and 1 or more if it is an array of matrices.
	transpose = For the matrix commands, specifies whether to transpose the matrix as the values are loaded into the uniform variable.
	value = For the vector and matrix commands, specifies a pointer to an array of $(I `count`) values that will be used to update the specified uniform variable.
	*/
	void uniformMatrix2x3fv(Int location, Sizei count, Boolean transpose, const(Float)* value);
	
	/**
	$(REF uniform) modifies the value of a uniform variable or a uniform variable array. The location of the uniform variable to be modified is specified by $(I `location`), which should be a value returned by $(REF getUniformLocation). $(REF uniform) operates on the program object that was made part of current state by calling $(REF useProgram).
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}) are used to change the value of the uniform variable specified by $(I `location`) using the values passed as arguments. The number specified in the command should match the number of components in the data type of the specified uniform variable (e.g., `1` for `float`, `int`, `unsigned int`, `bool`; `2` for `vec2`, `ivec2`, `uvec2`, `bvec2`, etc.). The suffix `f` indicates that floating-point values are being passed; the suffix `i` indicates that integer values are being passed; the suffix `ui` indicates that unsigned integer values are being passed, and this type should also match the data type of the specified uniform variable. The `i` variants of this function should be used to provide values for uniform variables defined as `int`, `ivec2`, `ivec3`, `ivec4`, or arrays of these. The `ui` variants of this function should be used to provide values for uniform variables defined as `unsigned int`, `uvec2`, `uvec3`, `uvec4`, or arrays of these. The `f` variants should be used to provide values for uniform variables of type `float`, `vec2`, `vec3`, `vec4`, or arrays of these. Either the `i`, `ui` or `f` variants may be used to provide values for uniform variables of type `bool`, `bvec2`, `bvec3`, `bvec4`, or arrays of these. The uniform variable will be set to `false` if the input value is 0 or 0.0f, and it will be set to `true` otherwise.
	
	All active uniform variables defined in a program object are initialized to 0 when the program object is linked successfully. They retain the values assigned to them by a call to $(REF uniform ) until the next successful link operation occurs on the program object, when they are once again initialized to 0.
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}v) can be used to modify a single uniform variable or a uniform variable array. These commands pass a count and a pointer to the values to be loaded into a uniform variable or a uniform variable array. A count of 1 should be used if modifying the value of a single uniform variable, and a count of 1 or greater can be used to modify an entire array or part of an array. When loading $(I n) elements starting at an arbitrary position $(I m) in a uniform variable array, elements $(I m) + $(I n) - 1 in the array will be replaced with the new values. If $(I `m`) + $(I `n`) - 1 is larger than the size of the uniform variable array, values for all array elements beyond the end of the array will be ignored. The number specified in the name of the command indicates the number of components for each element in $(I `value`), and it should match the number of components in the data type of the specified uniform variable (e.g., `1` for float, int, bool; `2` for vec2, ivec2, bvec2, etc.). The data type specified in the name of the command must match the data type for the specified uniform variable as described previously for $(REF uniform{1|2|3|4}{f|i|ui}).
	
	For uniform variable arrays, each element of the array is considered to be of the type indicated in the name of the command (e.g., $(REF uniform3f) or $(REF uniform3fv) can be used to load a uniform variable array of type vec3). The number of elements of the uniform variable array to be modified is specified by $(I `count`)
	
	The commands $(REF uniformMatrix{2|3|4|2x3|3x2|2x4|4x2|3x4|4x3}fv) are used to modify a matrix or an array of matrices. The numbers in the command name are interpreted as the dimensionality of the matrix. The number `2` indicates a 2 × 2 matrix (i.e., 4 values), the number `3` indicates a 3 × 3 matrix (i.e., 9 values), and the number `4` indicates a 4 × 4 matrix (i.e., 16 values). Non-square matrix dimensionality is explicit, with the first number representing the number of columns and the second number representing the number of rows. For example, `2x4` indicates a 2 × 4 matrix with 2 columns and 4 rows (i.e., 8 values). If $(I `transpose`) is `FALSE`, each matrix is assumed to be supplied in column major order. If $(I `transpose`) is `TRUE`, each matrix is assumed to be supplied in row major order. The $(I `count`) argument indicates the number of matrices to be passed. A count of 1 should be used if modifying the value of a single matrix, and a count greater than 1 can be used to modify an array of matrices.
	
	Params:
	location = Specifies the location of the uniform variable to be modified.
	count = For the vector ($(REF uniform*v)) commands, specifies the number of elements that are to be modified. This should be 1 if the targeted uniform variable is not an array, and 1 or more if it is an array. 
	
	 For the matrix ($(REF uniformMatrix*)) commands, specifies the number of matrices that are to be modified. This should be 1 if the targeted uniform variable is not an array of matrices, and 1 or more if it is an array of matrices.
	transpose = For the matrix commands, specifies whether to transpose the matrix as the values are loaded into the uniform variable.
	value = For the vector and matrix commands, specifies a pointer to an array of $(I `count`) values that will be used to update the specified uniform variable.
	*/
	void uniformMatrix3x2fv(Int location, Sizei count, Boolean transpose, const(Float)* value);
	
	/**
	$(REF uniform) modifies the value of a uniform variable or a uniform variable array. The location of the uniform variable to be modified is specified by $(I `location`), which should be a value returned by $(REF getUniformLocation). $(REF uniform) operates on the program object that was made part of current state by calling $(REF useProgram).
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}) are used to change the value of the uniform variable specified by $(I `location`) using the values passed as arguments. The number specified in the command should match the number of components in the data type of the specified uniform variable (e.g., `1` for `float`, `int`, `unsigned int`, `bool`; `2` for `vec2`, `ivec2`, `uvec2`, `bvec2`, etc.). The suffix `f` indicates that floating-point values are being passed; the suffix `i` indicates that integer values are being passed; the suffix `ui` indicates that unsigned integer values are being passed, and this type should also match the data type of the specified uniform variable. The `i` variants of this function should be used to provide values for uniform variables defined as `int`, `ivec2`, `ivec3`, `ivec4`, or arrays of these. The `ui` variants of this function should be used to provide values for uniform variables defined as `unsigned int`, `uvec2`, `uvec3`, `uvec4`, or arrays of these. The `f` variants should be used to provide values for uniform variables of type `float`, `vec2`, `vec3`, `vec4`, or arrays of these. Either the `i`, `ui` or `f` variants may be used to provide values for uniform variables of type `bool`, `bvec2`, `bvec3`, `bvec4`, or arrays of these. The uniform variable will be set to `false` if the input value is 0 or 0.0f, and it will be set to `true` otherwise.
	
	All active uniform variables defined in a program object are initialized to 0 when the program object is linked successfully. They retain the values assigned to them by a call to $(REF uniform ) until the next successful link operation occurs on the program object, when they are once again initialized to 0.
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}v) can be used to modify a single uniform variable or a uniform variable array. These commands pass a count and a pointer to the values to be loaded into a uniform variable or a uniform variable array. A count of 1 should be used if modifying the value of a single uniform variable, and a count of 1 or greater can be used to modify an entire array or part of an array. When loading $(I n) elements starting at an arbitrary position $(I m) in a uniform variable array, elements $(I m) + $(I n) - 1 in the array will be replaced with the new values. If $(I `m`) + $(I `n`) - 1 is larger than the size of the uniform variable array, values for all array elements beyond the end of the array will be ignored. The number specified in the name of the command indicates the number of components for each element in $(I `value`), and it should match the number of components in the data type of the specified uniform variable (e.g., `1` for float, int, bool; `2` for vec2, ivec2, bvec2, etc.). The data type specified in the name of the command must match the data type for the specified uniform variable as described previously for $(REF uniform{1|2|3|4}{f|i|ui}).
	
	For uniform variable arrays, each element of the array is considered to be of the type indicated in the name of the command (e.g., $(REF uniform3f) or $(REF uniform3fv) can be used to load a uniform variable array of type vec3). The number of elements of the uniform variable array to be modified is specified by $(I `count`)
	
	The commands $(REF uniformMatrix{2|3|4|2x3|3x2|2x4|4x2|3x4|4x3}fv) are used to modify a matrix or an array of matrices. The numbers in the command name are interpreted as the dimensionality of the matrix. The number `2` indicates a 2 × 2 matrix (i.e., 4 values), the number `3` indicates a 3 × 3 matrix (i.e., 9 values), and the number `4` indicates a 4 × 4 matrix (i.e., 16 values). Non-square matrix dimensionality is explicit, with the first number representing the number of columns and the second number representing the number of rows. For example, `2x4` indicates a 2 × 4 matrix with 2 columns and 4 rows (i.e., 8 values). If $(I `transpose`) is `FALSE`, each matrix is assumed to be supplied in column major order. If $(I `transpose`) is `TRUE`, each matrix is assumed to be supplied in row major order. The $(I `count`) argument indicates the number of matrices to be passed. A count of 1 should be used if modifying the value of a single matrix, and a count greater than 1 can be used to modify an array of matrices.
	
	Params:
	location = Specifies the location of the uniform variable to be modified.
	count = For the vector ($(REF uniform*v)) commands, specifies the number of elements that are to be modified. This should be 1 if the targeted uniform variable is not an array, and 1 or more if it is an array. 
	
	 For the matrix ($(REF uniformMatrix*)) commands, specifies the number of matrices that are to be modified. This should be 1 if the targeted uniform variable is not an array of matrices, and 1 or more if it is an array of matrices.
	transpose = For the matrix commands, specifies whether to transpose the matrix as the values are loaded into the uniform variable.
	value = For the vector and matrix commands, specifies a pointer to an array of $(I `count`) values that will be used to update the specified uniform variable.
	*/
	void uniformMatrix2x4fv(Int location, Sizei count, Boolean transpose, const(Float)* value);
	
	/**
	$(REF uniform) modifies the value of a uniform variable or a uniform variable array. The location of the uniform variable to be modified is specified by $(I `location`), which should be a value returned by $(REF getUniformLocation). $(REF uniform) operates on the program object that was made part of current state by calling $(REF useProgram).
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}) are used to change the value of the uniform variable specified by $(I `location`) using the values passed as arguments. The number specified in the command should match the number of components in the data type of the specified uniform variable (e.g., `1` for `float`, `int`, `unsigned int`, `bool`; `2` for `vec2`, `ivec2`, `uvec2`, `bvec2`, etc.). The suffix `f` indicates that floating-point values are being passed; the suffix `i` indicates that integer values are being passed; the suffix `ui` indicates that unsigned integer values are being passed, and this type should also match the data type of the specified uniform variable. The `i` variants of this function should be used to provide values for uniform variables defined as `int`, `ivec2`, `ivec3`, `ivec4`, or arrays of these. The `ui` variants of this function should be used to provide values for uniform variables defined as `unsigned int`, `uvec2`, `uvec3`, `uvec4`, or arrays of these. The `f` variants should be used to provide values for uniform variables of type `float`, `vec2`, `vec3`, `vec4`, or arrays of these. Either the `i`, `ui` or `f` variants may be used to provide values for uniform variables of type `bool`, `bvec2`, `bvec3`, `bvec4`, or arrays of these. The uniform variable will be set to `false` if the input value is 0 or 0.0f, and it will be set to `true` otherwise.
	
	All active uniform variables defined in a program object are initialized to 0 when the program object is linked successfully. They retain the values assigned to them by a call to $(REF uniform ) until the next successful link operation occurs on the program object, when they are once again initialized to 0.
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}v) can be used to modify a single uniform variable or a uniform variable array. These commands pass a count and a pointer to the values to be loaded into a uniform variable or a uniform variable array. A count of 1 should be used if modifying the value of a single uniform variable, and a count of 1 or greater can be used to modify an entire array or part of an array. When loading $(I n) elements starting at an arbitrary position $(I m) in a uniform variable array, elements $(I m) + $(I n) - 1 in the array will be replaced with the new values. If $(I `m`) + $(I `n`) - 1 is larger than the size of the uniform variable array, values for all array elements beyond the end of the array will be ignored. The number specified in the name of the command indicates the number of components for each element in $(I `value`), and it should match the number of components in the data type of the specified uniform variable (e.g., `1` for float, int, bool; `2` for vec2, ivec2, bvec2, etc.). The data type specified in the name of the command must match the data type for the specified uniform variable as described previously for $(REF uniform{1|2|3|4}{f|i|ui}).
	
	For uniform variable arrays, each element of the array is considered to be of the type indicated in the name of the command (e.g., $(REF uniform3f) or $(REF uniform3fv) can be used to load a uniform variable array of type vec3). The number of elements of the uniform variable array to be modified is specified by $(I `count`)
	
	The commands $(REF uniformMatrix{2|3|4|2x3|3x2|2x4|4x2|3x4|4x3}fv) are used to modify a matrix or an array of matrices. The numbers in the command name are interpreted as the dimensionality of the matrix. The number `2` indicates a 2 × 2 matrix (i.e., 4 values), the number `3` indicates a 3 × 3 matrix (i.e., 9 values), and the number `4` indicates a 4 × 4 matrix (i.e., 16 values). Non-square matrix dimensionality is explicit, with the first number representing the number of columns and the second number representing the number of rows. For example, `2x4` indicates a 2 × 4 matrix with 2 columns and 4 rows (i.e., 8 values). If $(I `transpose`) is `FALSE`, each matrix is assumed to be supplied in column major order. If $(I `transpose`) is `TRUE`, each matrix is assumed to be supplied in row major order. The $(I `count`) argument indicates the number of matrices to be passed. A count of 1 should be used if modifying the value of a single matrix, and a count greater than 1 can be used to modify an array of matrices.
	
	Params:
	location = Specifies the location of the uniform variable to be modified.
	count = For the vector ($(REF uniform*v)) commands, specifies the number of elements that are to be modified. This should be 1 if the targeted uniform variable is not an array, and 1 or more if it is an array. 
	
	 For the matrix ($(REF uniformMatrix*)) commands, specifies the number of matrices that are to be modified. This should be 1 if the targeted uniform variable is not an array of matrices, and 1 or more if it is an array of matrices.
	transpose = For the matrix commands, specifies whether to transpose the matrix as the values are loaded into the uniform variable.
	value = For the vector and matrix commands, specifies a pointer to an array of $(I `count`) values that will be used to update the specified uniform variable.
	*/
	void uniformMatrix4x2fv(Int location, Sizei count, Boolean transpose, const(Float)* value);
	
	/**
	$(REF uniform) modifies the value of a uniform variable or a uniform variable array. The location of the uniform variable to be modified is specified by $(I `location`), which should be a value returned by $(REF getUniformLocation). $(REF uniform) operates on the program object that was made part of current state by calling $(REF useProgram).
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}) are used to change the value of the uniform variable specified by $(I `location`) using the values passed as arguments. The number specified in the command should match the number of components in the data type of the specified uniform variable (e.g., `1` for `float`, `int`, `unsigned int`, `bool`; `2` for `vec2`, `ivec2`, `uvec2`, `bvec2`, etc.). The suffix `f` indicates that floating-point values are being passed; the suffix `i` indicates that integer values are being passed; the suffix `ui` indicates that unsigned integer values are being passed, and this type should also match the data type of the specified uniform variable. The `i` variants of this function should be used to provide values for uniform variables defined as `int`, `ivec2`, `ivec3`, `ivec4`, or arrays of these. The `ui` variants of this function should be used to provide values for uniform variables defined as `unsigned int`, `uvec2`, `uvec3`, `uvec4`, or arrays of these. The `f` variants should be used to provide values for uniform variables of type `float`, `vec2`, `vec3`, `vec4`, or arrays of these. Either the `i`, `ui` or `f` variants may be used to provide values for uniform variables of type `bool`, `bvec2`, `bvec3`, `bvec4`, or arrays of these. The uniform variable will be set to `false` if the input value is 0 or 0.0f, and it will be set to `true` otherwise.
	
	All active uniform variables defined in a program object are initialized to 0 when the program object is linked successfully. They retain the values assigned to them by a call to $(REF uniform ) until the next successful link operation occurs on the program object, when they are once again initialized to 0.
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}v) can be used to modify a single uniform variable or a uniform variable array. These commands pass a count and a pointer to the values to be loaded into a uniform variable or a uniform variable array. A count of 1 should be used if modifying the value of a single uniform variable, and a count of 1 or greater can be used to modify an entire array or part of an array. When loading $(I n) elements starting at an arbitrary position $(I m) in a uniform variable array, elements $(I m) + $(I n) - 1 in the array will be replaced with the new values. If $(I `m`) + $(I `n`) - 1 is larger than the size of the uniform variable array, values for all array elements beyond the end of the array will be ignored. The number specified in the name of the command indicates the number of components for each element in $(I `value`), and it should match the number of components in the data type of the specified uniform variable (e.g., `1` for float, int, bool; `2` for vec2, ivec2, bvec2, etc.). The data type specified in the name of the command must match the data type for the specified uniform variable as described previously for $(REF uniform{1|2|3|4}{f|i|ui}).
	
	For uniform variable arrays, each element of the array is considered to be of the type indicated in the name of the command (e.g., $(REF uniform3f) or $(REF uniform3fv) can be used to load a uniform variable array of type vec3). The number of elements of the uniform variable array to be modified is specified by $(I `count`)
	
	The commands $(REF uniformMatrix{2|3|4|2x3|3x2|2x4|4x2|3x4|4x3}fv) are used to modify a matrix or an array of matrices. The numbers in the command name are interpreted as the dimensionality of the matrix. The number `2` indicates a 2 × 2 matrix (i.e., 4 values), the number `3` indicates a 3 × 3 matrix (i.e., 9 values), and the number `4` indicates a 4 × 4 matrix (i.e., 16 values). Non-square matrix dimensionality is explicit, with the first number representing the number of columns and the second number representing the number of rows. For example, `2x4` indicates a 2 × 4 matrix with 2 columns and 4 rows (i.e., 8 values). If $(I `transpose`) is `FALSE`, each matrix is assumed to be supplied in column major order. If $(I `transpose`) is `TRUE`, each matrix is assumed to be supplied in row major order. The $(I `count`) argument indicates the number of matrices to be passed. A count of 1 should be used if modifying the value of a single matrix, and a count greater than 1 can be used to modify an array of matrices.
	
	Params:
	location = Specifies the location of the uniform variable to be modified.
	count = For the vector ($(REF uniform*v)) commands, specifies the number of elements that are to be modified. This should be 1 if the targeted uniform variable is not an array, and 1 or more if it is an array. 
	
	 For the matrix ($(REF uniformMatrix*)) commands, specifies the number of matrices that are to be modified. This should be 1 if the targeted uniform variable is not an array of matrices, and 1 or more if it is an array of matrices.
	transpose = For the matrix commands, specifies whether to transpose the matrix as the values are loaded into the uniform variable.
	value = For the vector and matrix commands, specifies a pointer to an array of $(I `count`) values that will be used to update the specified uniform variable.
	*/
	void uniformMatrix3x4fv(Int location, Sizei count, Boolean transpose, const(Float)* value);
	
	/**
	$(REF uniform) modifies the value of a uniform variable or a uniform variable array. The location of the uniform variable to be modified is specified by $(I `location`), which should be a value returned by $(REF getUniformLocation). $(REF uniform) operates on the program object that was made part of current state by calling $(REF useProgram).
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}) are used to change the value of the uniform variable specified by $(I `location`) using the values passed as arguments. The number specified in the command should match the number of components in the data type of the specified uniform variable (e.g., `1` for `float`, `int`, `unsigned int`, `bool`; `2` for `vec2`, `ivec2`, `uvec2`, `bvec2`, etc.). The suffix `f` indicates that floating-point values are being passed; the suffix `i` indicates that integer values are being passed; the suffix `ui` indicates that unsigned integer values are being passed, and this type should also match the data type of the specified uniform variable. The `i` variants of this function should be used to provide values for uniform variables defined as `int`, `ivec2`, `ivec3`, `ivec4`, or arrays of these. The `ui` variants of this function should be used to provide values for uniform variables defined as `unsigned int`, `uvec2`, `uvec3`, `uvec4`, or arrays of these. The `f` variants should be used to provide values for uniform variables of type `float`, `vec2`, `vec3`, `vec4`, or arrays of these. Either the `i`, `ui` or `f` variants may be used to provide values for uniform variables of type `bool`, `bvec2`, `bvec3`, `bvec4`, or arrays of these. The uniform variable will be set to `false` if the input value is 0 or 0.0f, and it will be set to `true` otherwise.
	
	All active uniform variables defined in a program object are initialized to 0 when the program object is linked successfully. They retain the values assigned to them by a call to $(REF uniform ) until the next successful link operation occurs on the program object, when they are once again initialized to 0.
	
	The commands $(REF uniform{1|2|3|4}{f|i|ui}v) can be used to modify a single uniform variable or a uniform variable array. These commands pass a count and a pointer to the values to be loaded into a uniform variable or a uniform variable array. A count of 1 should be used if modifying the value of a single uniform variable, and a count of 1 or greater can be used to modify an entire array or part of an array. When loading $(I n) elements starting at an arbitrary position $(I m) in a uniform variable array, elements $(I m) + $(I n) - 1 in the array will be replaced with the new values. If $(I `m`) + $(I `n`) - 1 is larger than the size of the uniform variable array, values for all array elements beyond the end of the array will be ignored. The number specified in the name of the command indicates the number of components for each element in $(I `value`), and it should match the number of components in the data type of the specified uniform variable (e.g., `1` for float, int, bool; `2` for vec2, ivec2, bvec2, etc.). The data type specified in the name of the command must match the data type for the specified uniform variable as described previously for $(REF uniform{1|2|3|4}{f|i|ui}).
	
	For uniform variable arrays, each element of the array is considered to be of the type indicated in the name of the command (e.g., $(REF uniform3f) or $(REF uniform3fv) can be used to load a uniform variable array of type vec3). The number of elements of the uniform variable array to be modified is specified by $(I `count`)
	
	The commands $(REF uniformMatrix{2|3|4|2x3|3x2|2x4|4x2|3x4|4x3}fv) are used to modify a matrix or an array of matrices. The numbers in the command name are interpreted as the dimensionality of the matrix. The number `2` indicates a 2 × 2 matrix (i.e., 4 values), the number `3` indicates a 3 × 3 matrix (i.e., 9 values), and the number `4` indicates a 4 × 4 matrix (i.e., 16 values). Non-square matrix dimensionality is explicit, with the first number representing the number of columns and the second number representing the number of rows. For example, `2x4` indicates a 2 × 4 matrix with 2 columns and 4 rows (i.e., 8 values). If $(I `transpose`) is `FALSE`, each matrix is assumed to be supplied in column major order. If $(I `transpose`) is `TRUE`, each matrix is assumed to be supplied in row major order. The $(I `count`) argument indicates the number of matrices to be passed. A count of 1 should be used if modifying the value of a single matrix, and a count greater than 1 can be used to modify an array of matrices.
	
	Params:
	location = Specifies the location of the uniform variable to be modified.
	count = For the vector ($(REF uniform*v)) commands, specifies the number of elements that are to be modified. This should be 1 if the targeted uniform variable is not an array, and 1 or more if it is an array. 
	
	 For the matrix ($(REF uniformMatrix*)) commands, specifies the number of matrices that are to be modified. This should be 1 if the targeted uniform variable is not an array of matrices, and 1 or more if it is an array of matrices.
	transpose = For the matrix commands, specifies whether to transpose the matrix as the values are loaded into the uniform variable.
	value = For the vector and matrix commands, specifies a pointer to an array of $(I `count`) values that will be used to update the specified uniform variable.
	*/
	void uniformMatrix4x3fv(Int location, Sizei count, Boolean transpose, const(Float)* value);
	
	/**
	$(REF bindVertexArray) binds the vertex array object with name $(I `array`). $(I `array`) is the name of a vertex array object previously returned from a call to $(REF genVertexArrays), or zero to break the existing vertex array object binding.
	
	If no vertex array object with name $(I `array`) exists, one is created when $(I `array`) is first bound. If the bind is successful no change is made to the state of the vertex array object, and any previous vertex array object binding is broken.
	
	Params:
	array = Specifies the name of the vertex array to bind.
	*/
	void bindVertexArray(UInt array);
	
	/**
	$(REF deleteVertexArrays) deletes $(I `n`) vertex array objects whose names are stored in the array addressed by $(I `arrays`). Once a vertex array object is deleted it has no contents and its name is again unused. If a vertex array object that is currently bound is deleted, the binding for that object reverts to zero and the default vertex array becomes current. Unused names in $(I `arrays`) are silently ignored, as is the value zero.
	
	Params:
	n = Specifies the number of vertex array objects to be deleted.
	arrays = Specifies the address of an array containing the $(I `n`) names of the objects to be deleted.
	*/
	void deleteVertexArrays(Sizei n, const(UInt)* arrays);
	
	/**
	$(REF genVertexArrays) returns $(I `n`) vertex array object names in $(I `arrays`). There is no guarantee that the names form a contiguous set of integers; however, it is guaranteed that none of the returned names was in use immediately before the call to $(REF genVertexArrays).
	
	Vertex array object names returned by a call to $(REF genVertexArrays) are not returned by subsequent calls, unless they are first deleted with $(REF deleteVertexArrays).
	
	The names returned in $(I `arrays`) are marked as used, for the purposes of $(REF genVertexArrays) only, but they acquire state and type only when they are first bound.
	
	Params:
	n = Specifies the number of vertex array object names to generate.
	arrays = Specifies an array in which the generated vertex array object names are stored.
	*/
	void genVertexArrays(Sizei n, UInt* arrays);
	
	/**
	$(REF isVertexArray) returns `TRUE` if $(I `array`) is currently the name of a vertex array object. If $(I `array`) is zero, or if $(I `array`) is not the name of a vertex array object, or if an error occurs, $(REF isVertexArray) returns `FALSE`. If $(I `array`) is a name returned by $(REF genVertexArrays), by that has not yet been bound through a call to $(REF bindVertexArray), then the name is not a vertex array object and $(REF isVertexArray) returns `FALSE`.
	
	Params:
	array = Specifies a value that may be the name of a vertex array object.
	*/
	Boolean isVertexArray(UInt array);
	
	
}