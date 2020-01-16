{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE TemplateHaskell #-}

-- | TODO RGS: Docs
module Language.Haskell.TH.Syntax.QuoteSpec (main, spec) where

import Control.Exception (evaluate)
import Control.Monad.State

import Language.Haskell.TH.Syntax hiding (newName)
import Language.Haskell.TH.Syntax.Quote

import Prelude ()
import Prelude.Compat

import Test.Hspec

main :: IO ()
main = hspec spec

spec :: Spec
spec = parallel $ do
  describe "newName" $
    it "works on something that isn't a Quasi instance" $
      runPureQ (newName "a") `shouldBe` mkNameU "a" 0

  describe "unsafeQToQuote" $ do
    it "works on Quasi-less expressions" $ do
      $(unsafeQToQuote [| "abc" |])         `shouldBe` "abc"
      runPureQ (unsafeQToQuote [| "abc" |]) `shouldBe` LitE (StringL "abc")

    it "errors on Quasi-ful expressions" $
      evaluate (runPureQ (unsafeQToQuote (qReport True "Explosion in 3... 2... 1...")))
        `shouldThrow` errorCall "`unsafeQToQuote` does not support code that uses qReport"

newtype PureQ a = MkPureQ (State Uniq a)
  deriving (Functor, Applicative, Monad, MonadState Uniq)

runPureQ :: PureQ a -> a
runPureQ m = case m of MkPureQ m' -> evalState m' 0

instance Quote PureQ where
  newName s = state $ \i -> (mkNameU s i, i + 1)
