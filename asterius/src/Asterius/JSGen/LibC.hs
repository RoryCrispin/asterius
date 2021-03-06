{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE StrictData #-}

module Asterius.JSGen.LibC
  ( LibCOpts (..),
    defLibCOpts,
    genLibC,
  )
where

import qualified Asterius.BuildInfo as A
import Asterius.Internals.Temp
import qualified Data.ByteString as BS
import Data.Traversable
import Distribution.Simple.CCompiler
import Distribution.Simple.Utils
import System.Directory
import System.Environment.Blank
import System.FilePath
import System.Process

data LibCOpts = LibCOpts
  { globalBase :: ~Int,
    exports :: [String]
  }

defLibCOpts :: LibCOpts
defLibCOpts =
  LibCOpts
    { globalBase = error "globalBase not set",
      exports =
        [ "aligned_alloc",
          "free",
          "memchr",
          "memcpy",
          "strlen"
        ]
    }

genLibC :: LibCOpts -> IO BS.ByteString
genLibC LibCOpts {..} = do
  wasi_sdk <- do
    mp <- getEnv "WASI_SDK_PATH"
    case mp of
      Just p -> pure p
      _ -> fail "WASI_SDK_PATH not set"
  let cish_dir = A.dataDir </> "libc"
  cish <- map (cish_dir </>) <$> listDirectory cish_dir
  let cbits = filter isC cish
      cxxbits = filter isCxx cish
  withTempDir "asterius" $ \tmpdir -> do
    let common_opts =
          [ "--sysroot=" <> wasi_sdk </> "share" </> "wasi-sysroot",
            "-I" <> (A.ahcLibDir </> "include"),
            "-Oz",
            "-flto"
          ]
    c_objs <- for cbits $ \src -> do
      o <- newTempFile tmpdir "tmp.o"
      callProcess (wasi_sdk </> "bin" </> "clang") $
        common_opts
          <> ["-c", "-o", o, src]
      pure o
    cxx_objs <- for cxxbits $ \src -> do
      o <- newTempFile tmpdir "tmp.o"
      callProcess (wasi_sdk </> "bin" </> "clang++") $
        common_opts
          <> ["-c", "-o", o, src]
      pure o
    result_obj <- newTempFile tmpdir "tmp.wasm"
    callProcess (wasi_sdk </> "bin" </> "clang++") $
      common_opts
        <> ["-Wl,--export=" <> f | f <- ordNub exports]
        <> [ "-Wl,--allow-undefined",
             "-Wl,--compress-relocations",
             "-Wl,--export-table",
             "-Wl,--global-base=" <> show globalBase,
             "-Wl,--growable-table",
             "-Wl,--lto-O3",
             "-Wl,--strip-all"
           ]
        <> ["-o", result_obj]
        <> c_objs
        <> cxx_objs
    BS.readFile result_obj

isC :: FilePath -> Bool
isC = (== Just (C, True)) . filenameCDialect

isCxx :: FilePath -> Bool
isCxx = (== Just (CPlusPlus, True)) . filenameCDialect
