{-# LANGUAGE CPP #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE RankNTypes #-}

#if __GLASGOW_HASKELL__ >= 706
{-# LANGUAGE PolyKinds #-}
#endif

-- | TODO RGS: Docs
module Language.Haskell.TH.Syntax.Quote (
    -- TODO RGS: Some bullet points
    Quote(..)
#if MIN_VERSION_template_haskell(2,9,0)
  , unTypeQQuote
  , unsafeTExpCoerceQuote
#endif
  , liftQuote
#if MIN_VERSION_template_haskell(2,16,0)
  , liftTypedQuote
#endif

  , unsafeQToQuote
  ) where

import qualified Control.Monad.Fail as Fail
import Control.Monad.IO.Class (MonadIO(..))
import Language.Haskell.TH (Exp)
import Language.Haskell.TH.Syntax (Q, runQ, Quasi(..))
import qualified Language.Haskell.TH.Syntax as Syntax

#if !(MIN_VERSION_base(4,8,0))
import Control.Applicative
#endif

#if MIN_VERSION_template_haskell(2,16,0)
import GHC.Exts (RuntimeRep, TYPE)
#endif

-- TODO RGS: Use MIN_VERSION_template_haskell(2,17,0) when that's possible
#if __GLASGOW_HASKELL__ >= 811
import Language.Haskell.TH.Syntax (Quote(..), unsafeTExpCoerce, unTypeQ)
#else
import Language.Haskell.TH (Name)
#endif

-- TODO RGS: Use !(MIN_VERSION_template_haskell(2,17,0)) when that's possible
#if __GLASGOW_HASKELL__ < 811
-- TODO RGS: Consider revising this documentation, since it doesn't quite hold
-- true on old GHCs

-- | The 'Quote' class implements the minimal interface which is necessary for
-- desugaring quotations.
--
-- * The @Monad m@ superclass is needed to stitch together the different
-- AST fragments.
-- * 'newName' is used when desugaring binding structures such as lambdas
-- to generate fresh names.
--
-- Therefore the type of an untyped quotation in GHC is `Quote m => m Exp`
--
-- For many years the type of a quotation was fixed to be `Q Exp` but by
-- more precisely specifying the minimal interface it enables the `Exp` to
-- be extracted purely from the quotation without interacting with `Q`.
class ( Monad m
# if   !(MIN_VERSION_template_haskell(2,7,0))
      , Functor m
# elif !(MIN_VERSION_template_haskell(2,10,0))
      , Applicative m
# endif
      ) => Quote m where
  {- |
  Generate a fresh name, which cannot be captured.

  For example, this:

  @f = $(do
    nm1 <- newName \"x\"
    let nm2 = 'mkName' \"x\"
    return ('LamE' ['VarP' nm1] (LamE [VarP nm2] ('VarE' nm1)))
   )@

  will produce the splice

  >f = \x0 -> \x -> x0

  In particular, the occurrence @VarE nm1@ refers to the binding @VarP nm1@,
  and is not captured by the binding @VarP nm2@.

  Although names generated by @newName@ cannot /be captured/, they can
  /capture/ other names. For example, this:

  >g = $(do
  >  nm1 <- newName "x"
  >  let nm2 = mkName "x"
  >  return (LamE [VarP nm2] (LamE [VarP nm1] (VarE nm2)))
  > )

  will produce the splice

  >g = \x -> \x0 -> x0

  since the occurrence @VarE nm2@ is captured by the innermost binding
  of @x@, namely @VarP nm1@.
  -}
  newName :: String -> m Name

instance Quote Q where
  newName = qNewName
#endif

-- TODO RGS: Explain the -Quote suffix on each of these functions

#if MIN_VERSION_template_haskell(2,9,0)
-- | Discard the type annotation and produce a plain Template Haskell
-- expression
--
-- Levity-polymorphic since /template-haskell-2.16.0.0/.
unTypeQQuote ::
# if MIN_VERSION_template_haskell(2,16,0)
  forall (r :: RuntimeRep) (a :: TYPE r) m .
# else
  forall a m .
# endif
  Quote m => m (Syntax.TExp a) -> m Exp
-- TODO RGS: Use MIN_VERSION_template_haskell(2,17,0) when that's possible
# if __GLASGOW_HASKELL__ >= 811
unTypeQQuote = unTypeQ
# else
unTypeQQuote m = do { Syntax.TExp e <- m
                    ; return e }
# endif

-- | Annotate the Template Haskell expression with a type
--
-- This is unsafe because GHC cannot check for you that the expression
-- really does have the type you claim it has.
--
-- Levity-polymorphic since /template-haskell-2.16.0.0/.
unsafeTExpCoerceQuote ::
# if MIN_VERSION_template_haskell(2,16,0)
  forall (r :: RuntimeRep) (a :: TYPE r) m .
# else
  forall a m .
# endif
  Quote m => m Exp -> m (Syntax.TExp a)
-- TODO RGS: Use MIN_VERSION_template_haskell(2,17,0) when that's possible
# if __GLASGOW_HASKELL__ >= 811
unsafeTExpCoerceQuote = unsafeTExpCoerce
# else
unsafeTExpCoerceQuote m = do { e <- m
                             ; return (Syntax.TExp e) }
# endif
#endif

-- | Turn a value into a Template Haskell expression, suitable for use in
-- a splice.
liftQuote :: (Syntax.Lift t, Quote m) => t -> m Exp
-- TODO RGS: Use MIN_VERSION_template_haskell(2,17,0) when that's possible
#if __GLASGOW_HASKELL__ >= 811
liftQuote = Syntax.lift
#else
liftQuote = unsafeQToQuote . Syntax.lift
#endif

#if MIN_VERSION_template_haskell(2,16,0)
liftTypedQuote :: (Syntax.Lift t, Quote m) => t -> m (Syntax.TExp t)
-- TODO RGS: Use MIN_VERSION_template_haskell(2,17,0) when that's possible
# if __GLASGOW_HASKELL__ >= 811
liftTypedQuote = Syntax.liftTyped
# else
liftTypedQuote = unsafeQToQuote . Syntax.liftTyped
# endif
#endif

-- TODO RGS: Docs
newtype QuoteToQuasi (m :: * -> *) a = QTQ { unQTQ :: m a }
  deriving (Functor, Applicative, Monad)

qtqError :: String -> a
qtqError name = error $ "`unsafeQToQuote` does not support code that uses " ++ name

instance Monad m => Fail.MonadFail (QuoteToQuasi m) where
  fail = qtqError "MonadFail.fail"

instance Monad m => MonadIO (QuoteToQuasi m) where
  liftIO = qtqError "liftIO"

instance Quote m => Quasi (QuoteToQuasi m) where
  qNewName s = QTQ (newName s)

  qRecover            = qtqError "qRecover"
  qReport             = qtqError "qReport"
  qReify              = qtqError "qReify"
  qLocation           = qtqError "qLocation"
  qRunIO              = qtqError "qRunIO"
#if MIN_VERSION_template_haskell(2,7,0)
  qReifyInstances     = qtqError "qReifyInstances"
  qLookupName         = qtqError "qLookupName"
  qAddDependentFile   = qtqError "qAddDependentFile"
# if MIN_VERSION_template_haskell(2,9,0)
  qReifyRoles         = qtqError "qReifyRoles"
  qReifyAnnotations   = qtqError "qReifyAnnotations"
  qReifyModule        = qtqError "qReifyModule"
  qAddTopDecls        = qtqError "qAddTopDecls"
  qAddModFinalizer    = qtqError "qAddModFinalizer"
  qGetQ               = qtqError "qGetQ"
  qPutQ               = qtqError "qPutQ"
# endif
# if MIN_VERSION_template_haskell(2,11,0)
  qReifyFixity        = qtqError "qReifyFixity"
  qReifyConStrictness = qtqError "qReifyConStrictness"
  qIsExtEnabled       = qtqError "qIsExtEnabled"
  qExtsEnabled        = qtqError "qExtsEnabled"
# endif
#elif MIN_VERSION_template_haskell(2,5,0)
  qClassInstances     = qtqError "qClassInstances"
#endif
#if MIN_VERSION_template_haskell(2,13,0)
  qAddCorePlugin      = qtqError "qAddCorePlugin"
#endif
#if MIN_VERSION_template_haskell(2,14,0)
  qAddForeignFilePath = qtqError "qAddForeignFilePath"
  qAddTempFile        = qtqError "qAddTempFile"
#elif MIN_VERSION_template_haskell(2,12,0)
  qAddForeignFile     = qtqError "qAddForeignFile"
#endif
#if MIN_VERSION_template_haskell(2,16,0)
  qReifyType          = qtqError "qReifyType"
#endif

-- TODO RGS: Docs
unsafeQToQuote :: Quote m => Q a -> m a
unsafeQToQuote = unQTQ . runQ