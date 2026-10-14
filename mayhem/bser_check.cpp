// Known-answer check of pybser's decoder: valid BSER documents must decode to the exact Python value.
// Prints one "OK <name>" / "FAIL <name> ..." line per case; mayhem/test.sh counts them.
#include <cstdio>
#include <cstring>
#include <string>

#include "watchman/python/pywatchman/bser.h"

struct Case {
  const char* name;
  std::string bytes;
  const char* expected;
};

static std::string repr_of(PyObject* o) {
  PyObject* r = PyObject_Repr(o);
  if (!r) {
    PyErr_Clear();
    return "<repr failed>";
  }
  const char* s = PyUnicode_AsUTF8(r);
  std::string out = s ? s : "<utf8 failed>";
  Py_DECREF(r);
  return out;
}

int main() {
  Py_InitializeEx(0);

  const Case cases[] = {
      {"int8", std::string("\x03\x7f", 2), "127"},
      {"int8-negative", std::string("\x03\xff", 2), "-1"},
      {"int16", std::string("\x04\x00\x01", 3), "256"},
      {"int32", std::string("\x05\x01\x00\x01\x00", 5), "65537"},
      {"int64", std::string("\x06\x01\x00\x00\x00\x01\x00\x00\x00", 9), "4294967297"},
      {"real", std::string("\x07\x00\x00\x00\x00\x00\x00\xf8\x3f", 9), "1.5"},
      {"true", std::string("\x08", 1), "True"},
      {"false", std::string("\x09", 1), "False"},
      {"null", std::string("\x0a", 1), "None"},
      {"bytestring", std::string("\x02\x03\x03" "abc", 6), "b'abc'"},
      {"utf8string", std::string("\x0d\x03\x02" "hi", 5), "'hi'"},
      {"array", std::string("\x00\x03\x03\x03\x01\x03\x02\x03\x03", 9), "[1, 2, 3]"},
      {"object", std::string("\x01\x03\x01\x02\x03\x01k\x03\x05", 9), "{'k': 5}"},
      {"template",
       std::string("\x0b\x00\x03\x01\x02\x03\x01" "a" "\x03\x02\x03\x07\x03\x08", 14),
       "[{'a': 7}, {'a': 8}]"},
      {"template-skip",
       std::string("\x0b\x00\x03\x01\x02\x03\x01" "a" "\x03\x02\x03\x07\x0c", 13),
       "[{'a': 7}, {'a': None}]"},
      {"nested",
       std::string("\x01\x03\x01\x02\x03\x01x\x00\x03\x02\x08\x0a", 12),
       "{'x': [True, None]}"},
  };

  int failed = 0;
  for (const Case& c : cases) {
    unser_ctx_t ctx{};
    ctx.is_mutable = 1;
    ctx.bser_version = 1;
    const char* p = c.bytes.data();
    PyObject* v = bser_loads_recursive(&p, p + c.bytes.size(), &ctx);
    if (!v) {
      PyErr_Clear();
      std::printf("FAIL %s: decode raised\n", c.name);
      failed++;
      continue;
    }
    std::string got = repr_of(v);
    Py_DECREF(v);
    if (got == c.expected) {
      std::printf("OK %s\n", c.name);
    } else {
      std::printf("FAIL %s: got %s expected %s\n", c.name, got.c_str(), c.expected);
      failed++;
    }
  }
  return failed ? 1 : 0;
}
