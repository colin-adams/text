module Data.Text

import Data.Text.Encoding
import Data.Text.Encoding.UTF8

%access public
%default total

abstract
record EncodedString : Encoding -> Type where
  EncS :
    (getBytes_ : ByteString)
    -> EncodedString e

-- Required because the autogenerated projection is not very useful.
getBytes : EncodedString e -> ByteString
getBytes (EncS bs) = bs

-- We define Text to be UTF8-encoded packed strings.
Text : Type
Text = EncodedString UTF8

-- Meant to be used infix: ("bytes" `asEncodedIn` UTF8).
-- It is up to the user to ensure that the ByteString has the right encoding.
asEncodedIn : ByteString -> (e : Encoding) -> EncodedString e
asEncodedIn bs e = EncS bs

-- A shortcut for the most common use case.
fromUTF8 : ByteString -> Text
fromUTF8 s = s `asEncodedIn` UTF8

private
foldl' :
  (ByteString -> Maybe (CodePoint, Nat))  -- The peek function
  -> (a -> CodePoint -> a)  -- The folding function
  -> a            -- The seed value
  -> Nat          -- Skip this number of bytes first
  -> Nat          -- Total string length
  -> ByteString   -- The bytes
  -> a
foldl' pE f z    Z     Z  bs = z
foldl' pE f z (S n)    Z  bs = z

foldl' pE f z (S n) (S l) bs with (unconsBS bs)  -- skip step
  | Nothing      = z
  | Just (x, xs) = foldl' pE f z n l xs

foldl' pE f z    Z  (S l) bs =
  case pE bs of
    Nothing        => z
    Just (c, skip) => case unconsBS bs of
      Nothing      => z
      Just (x, xs) => foldl' pE f (f z c) skip l xs

private
foldr' :
  (ByteString -> Maybe (CodePoint, Nat))  -- The peek function
  -> (CodePoint -> a -> a)  -- The folding function
  -> a            -- The seed value
  -> Nat          -- Skip this number of bytes first
  -> Nat          -- Total string length
  -> ByteString   -- The bytes
  -> a
foldr' pE f z    Z     Z  bs = z
foldr' pE f z (S n)    Z  bs = z

foldr' pE f z (S n) (S l) bs with (unconsBS bs)  -- skip step
  | Nothing      = z
  | Just (x, xs) = foldr' pE f z n l xs

foldr' pE f z    Z  (S l) bs =
  case pE bs of
    Nothing        => z
    Just (c, skip) => f c (lazy (case unconsBS bs of
      Nothing      => z
      Just (x, xs) => foldr' pE f z skip l xs))

foldr : {e : Encoding} -> (CodePoint -> a -> a) -> a -> EncodedString e -> a
foldr {e = Enc pE _} f z (EncS bs) = foldr' pE f z 0 (lengthBS bs) bs

foldl : {e : Encoding} -> (a -> CodePoint -> a) -> a -> EncodedString e -> a
foldl {e = Enc pE _} f z (EncS bs) = foldl' pE f z 0 (lengthBS bs) bs

-- Will overflow stack on long texts. Use reverse . foldl to avoid that.
unpack : {e : Encoding} -> EncodedString e -> List CodePoint
unpack {e = Enc pE _} = Data.Text.foldr (::) []

pack : {e : Encoding} -> List CodePoint -> EncodedString e
pack {e = Enc _ eE} = EncS . foldr (appendBS . eE) emptyBS

-- O(1). Construct a single-char encoded string.
singleton : {e : Encoding} -> CodePoint -> EncodedString e
singleton {e = Enc _ eE} c = EncS (eE c)

-- O(1). Construct an empty encoded string.
empty : EncodedString e
empty = EncS emptyBS

-- O(n). Prepend a single character.
cons : {e : Encoding} -> CodePoint -> EncodedString e -> EncodedString e
cons {e = Enc pE eE} c (EncS bs) = EncS (eE c `appendBS` bs)

-- O(1). Uncons the first character or return Nothing if the string is empty.
uncons : {e : Encoding} -> EncodedString e -> Maybe (CodePoint, EncodedString e)
uncons {e = Enc pE eE} (EncS bs) with (pE bs)
  | Just (c, skip) = Just (c, EncS $ dropBS skip bs)
  | Nothing        = Nothing

-- O(n). Append a single character.
snoc : {e : Encoding} -> CodePoint -> EncodedString e -> EncodedString e
snoc {e = Enc pE eE} c (EncS bs) = EncS (bs `appendBS` eE c)

-- O(1). Get the first character or Nothing if the string is empty.
head : {e : Encoding} -> EncodedString e -> Maybe CodePoint
head {e = Enc pE eE} = map fst . pE . getBytes

-- O(1). Get the tail of the string or Nothing if the string is empty.
tail : {e : Encoding} -> EncodedString e -> Maybe (EncodedString e)
tail {e = Enc pE eE} = map snd . uncons

-- O(n). Get the length of the string. (Count all codepoints.)
length : EncodedString e -> Nat
length = Data.Text.foldl (\n => \_ => S n) Z

-- O(n_left). Concatenate two strings.
append : EncodedString e -> EncodedString e -> EncodedString e
append (EncS s) (EncS s') = EncS (s `appendBS` s')

-- init is unsupported
-- last is unsupported

-- O(1). Determines whether the string is empty.
null : EncodedString e -> Bool
null (EncS bs) = nullBS bs

-- O(n). Will overflow the stack for very long strings.
map : (CodePoint -> CodePoint) -> EncodedString e -> EncodedString e'
map {e' = Enc _ eE'} f = foldr (cons . f) empty

instance Cast (EncodedString e) (EncodedString e') where
  cast = map id

-- O(n). Concatenate with separators.
intercalate : EncodedString e -> List (EncodedString e) -> EncodedString e
intercalate sep []        = empty
intercalate sep [x]       = x
intercalate sep (x :: xs) = x `append` (sep `append` intercalate sep xs)

-- O(n). Rearrange the codepoints in the opposite order.
-- TODO: is it correct to do this in Unicode?
reverse : EncodedString e -> EncodedString e
reverse = foldl (flip cons) empty

-- O(n). Concatenate all strings in the list.
concat : List (EncodedString e) -> EncodedString e
concat [] = empty
concat (x :: xs) = x `append` concat xs

-- O(n). Concatenate all strings resulting from a codepoint mapping.
concatMap : (CodePoint -> EncodedString e) -> EncodedString e -> EncodedString e
concatMap f = foldr (append . f) empty

-- O(n). Check whether any codepoint has the specified property.
-- Will overflow the stack on very long texts
-- but will exit early if the desired codepoint is found.
any : (CodePoint -> Bool) -> EncodedString e -> Bool
any p = foldr ((||) . p) False

-- O(n). Check whether all codepoints have the specified property.
all : (CodePoint -> Bool) -> EncodedString e -> Bool
all p = foldl (\r => \c => r && p c) True

-- O(n*|w|). Repeat the string n times.
replicate : Nat -> EncodedString e -> EncodedString e
replicate    Z  s = empty
replicate (S n) s = s `append` replicate n s

{-
lines : EncodedString e -> List (EncodedString e)
lines s = ?linesMV
-}

{-
-- O(n).
take : Nat -> EncodedString e -> EncodedString e
take Z _ = empty
take {e = Enc pE eE} (S n) (EncS bs) with (pE

Requires `recurse', a generalisation of foldr/foldl.
-}
