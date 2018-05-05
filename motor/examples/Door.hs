{-# LANGUAGE ConstraintKinds            #-}
{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GADTs                      #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase                 #-}
{-# LANGUAGE OverloadedLabels           #-}
{-# LANGUAGE PolyKinds                  #-}
{-# LANGUAGE RankNTypes                 #-}
{-# LANGUAGE RebindableSyntax           #-}
{-# LANGUAGE StandaloneDeriving         #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE TypeOperators              #-}
module Examples.Door where

import           Prelude

import           Control.Concurrent     (threadDelay)
import           Control.Monad.Indexed
import           Control.Monad.IO.Class
import           Data.Row.Records
import           GHC.OverloadedLabels

import           Motor.FSM

-- * Protocol (Abstract state types)

-- We only use marker types for states in the Door protocol.
data Open
data Closed

class MonadFSM m => Door m where
  -- The associated type lets the instance choose the concrete state
  -- data type.
  type State m :: * -> *

  -- Events:
  initial :: Name n -> Actions m '[ n !+ State m Closed ] r ()
  currentDoor :: Name n -> Get m r n
  open :: Name n -> Actions m '[ n :-> State m Closed !--> State m Open ] r ()
  close :: Name n -> Actions m '[ n :-> State m Open !--> State m Closed ] r ()
  end :: Name n -> Actions m '[ n !- State m Closed ] r ()

-- * Implemention (Concrete types)
--
-- This could be in another module, hiding the constructors.

newtype ConsoleDoor m (i :: Row *) (o :: Row *) a =
  ConsoleDoor { runConsoleDoor :: FSM m i o a }
  deriving (IxFunctor, IxPointed, IxApplicative, IxMonad, MonadFSM)

run :: Monad m => ConsoleDoor m Empty Empty () -> m ()
run = runFSM . runConsoleDoor

deriving instance Monad m => Functor (ConsoleDoor m i i)
deriving instance Monad m => Applicative (ConsoleDoor m i i)
deriving instance Monad m => Monad (ConsoleDoor m i i)

instance (MonadIO m) => MonadIO (ConsoleDoor m i i) where
  liftIO = ConsoleDoor . liftIO

data DoorState s where
  Open :: DoorState Open
  Closed :: DoorState Closed

-- Extremely boring implementation:
instance (Monad m) => Door (ConsoleDoor m) where
  type State (ConsoleDoor m) = DoorState
  initial n = new n Closed
  -- Also trying the get operator here.
  currentDoor = get
  open n = enter n Open
  close n = enter n Closed
  end = delete

-- * Runner Program

-- This uses the protocol to define a program using the Door protocol.

sleep :: (MonadIO (m i i)) => Int -> m (i :: Row *) (i :: Row *) ()
sleep seconds = liftIO (threadDelay (seconds * 1000000))

confirm :: (MonadIO (m i i)) => String -> m (i :: Row *) (i :: Row *) Bool
confirm s = liftIO (putStrLn s >> ("y" ==) <$> getLine)

traceDoor :: (MonadIO m) => Name n -> ConsoleDoor m (n .== DoorState s) (n .== DoorState s) ()
traceDoor n = currentDoor n >>>= \case
  Open -> liftIO (putStrLn "The door is open.")
  Closed -> liftIO (putStrLn "The door is closed.")

type OpenAndClose m n o c =
    ( Door m
    , Modify n (State m Open) c ~ o
    , Modify n (State m Closed) o ~ c
    )

type OpenAndCloseIO m n o c =
    ( OpenAndClose m n o c
    , MonadIO (m o o)
    , MonadIO (m c c)
    )

inClosed :: (OpenAndCloseIO m n o c) => Name n -> m c (c .- n) ()
inClosed door = confirm "Open door?" >>>= \case
  True  -> open door >>>= const (inOpen door)
  False -> end door

inOpen :: (OpenAndCloseIO m n o c) => Name n -> m o (c .- n) ()
inOpen door = confirm "The door must be closed. OK?" >>>= \case
  True  -> close door >>>= const (inClosed door)
  False -> inOpen door

-- The program initializes a door, and starts the looping between
-- open/closed.
main :: IO ()
main = run $ initial #door >>>= const (inClosed #door)

{- $example-run

Running this program can look like this:

>>> main
Open door?
y
The door must be closed. OK?
y
Open door?
y
The door must be closed. OK?
n
The door must be closed. OK?
n
The door must be closed. OK?
n
The door must be closed. OK?
y
Open door?
n
-}
