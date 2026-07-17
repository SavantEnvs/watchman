#![no_main]
use libfuzzer_sys::fuzz_target;

use serde::{Deserialize, Serialize};
use serde_bser::de::from_slice;
use serde_bser::ser::serialize;

#[derive(Debug, Serialize, Deserialize, PartialEq)]
enum PlainEnum {
    A,
    B,
    C,
    D,
}

#[derive(Debug, Serialize, Deserialize, PartialEq)]
enum Enum {
    A(u8),
    B(()),
    C(Vec<PlainEnum>),
    D(i128),
}

#[derive(Debug, Serialize, Deserialize, PartialEq)]
enum FloatEnum {
    A(Enum),
    E(Option<f32>),
}

#[derive(Debug, Serialize, Deserialize, PartialEq)]
struct Struct {
    _a: (),
    _b: u8,
    _c: Vec<Enum>,
    _d: (u128, i8, (), PlainEnum, String),
}

#[derive(Debug, Serialize, Deserialize, PartialEq)]
struct FloatStruct {
    _a: Struct,
    _b: f64,
}

macro_rules! round_trip {
    ($t:expr, $ty:ty, $to_bytes:ident, $from_bytes:ident, $equality:expr) => {{
        let mut ser = $to_bytes(&$t).expect("a deserialized type should serialize");
        #[cfg(feature = "debug")]
        dbg!(&ser);

        let des: $ty = $from_bytes(&mut ser).expect("a serialized type should deserialize");
        #[cfg(feature = "debug")]
        dbg!(&des);

        if $equality {
            assert_eq!($t, des, "roundtripped object changed");
        }
    }};
}

fn serialize_to_vec(value: impl serde::Serialize) -> Option<Vec<u8>> {
    let mut v = Vec::new();
    serialize(&mut v, value).ok()?;
    Some(v)
}

macro_rules! from_bytes {
    ($ty:ty, $data:expr, $equality:expr) => {{
        // Normal T

        let x: Result<$ty, _> = from_slice(&$data);
        if let Ok(t) = x {
            round_trip!(t, $ty, serialize_to_vec, from_slice, $equality);
        }

        // Option<T>

        let x: Result<Option<$ty>, _> = from_slice(&$data);
        if let Ok(t) = x {
            round_trip!(t, Option<$ty>, serialize_to_vec, from_slice, $equality);
        }

        // Vec<T>

        let x: Result<Vec<$ty>, _> = from_slice(&$data);
        if let Ok(t) = x {
            round_trip!(t, Vec<$ty>, serialize_to_vec, from_slice, $equality);
        }
    }};
}

fuzz_target!(|data: &[u8]| {
    from_bytes!(bool, data, true);
    from_bytes!(i8, data, true);
    from_bytes!(i16, data, true);
    from_bytes!(i32, data, true);
    from_bytes!(i64, data, true);
    from_bytes!(i128, data, true);
    from_bytes!(u8, data, true);
    from_bytes!(u16, data, true);
    from_bytes!(u32, data, true);
    from_bytes!(u64, data, true);
    from_bytes!(u128, data, true);
    from_bytes!(f32, data, false);
    from_bytes!(f64, data, false);
    from_bytes!(char, data, true);
    from_bytes!(&str, data, true);
    from_bytes!((), data, true);
    from_bytes!(PlainEnum, data, true);
    from_bytes!(Enum, data, true);
    from_bytes!(FloatEnum, data, false);
    from_bytes!(Struct, data, true);
    from_bytes!(FloatStruct, data, false);
});
