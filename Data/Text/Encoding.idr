module Data.Text.Encoding

import Data.Bits
import Data.Text.ByteString

%access public

CodePoint : Type
CodePoint = Bits 32

record Encoding : Type where
  Enc :
       -- unconsE returns the first code point
       -- and the predecessor of the number of bytes
       -- to skip to get past the first code point.
       --
       -- In other words, returning (c, n)
       -- will make the decoder skip (S n) bytes.
       (peek_   : ByteString -> Maybe (CodePoint, Nat))
    -> (encode_ : CodePoint -> ByteString)
    -> Encoding
