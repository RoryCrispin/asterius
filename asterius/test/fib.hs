import System.Environment
import System.Process

main :: IO ()
main = do
  args <- getArgs
  callProcess "ahc-link" $ ["--input-hs", "test/fib/fib.hs", "--run"] <> args
