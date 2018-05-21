module UI where

import Control.Monad.IO.Class (liftIO)

import           Brick
import qualified Brick.Focus                as F
import qualified Brick.Widgets.Border       as B
import qualified Brick.Widgets.Border.Style as BS
import qualified Brick.Widgets.Center       as C
import qualified Brick.Widgets.Core         as BC
import qualified Brick.Widgets.Edit         as E
import qualified Brick.Widgets.List         as L
import           Data.Function              ((&))
import           Data.List.NonEmpty         (NonEmpty (..))
import           Data.Text                  (Text)
import qualified Data.Text                  as T
import qualified Data.Vector                as Vec
import           Fmt                        (fmt)
import           Fmt.Time                   (dateDashF)
import qualified Graphics.Vty               as V
import           Lens.Micro                 ((%~), (.~), (^.))
import           Lens.Micro.TH              (makeLenses)

import qualified Config
import qualified Lib


data State = State
    { _focusRing  :: F.FocusRing Name
    , _library    :: L.List Name Lib.FileInfo
    , _inbox      :: L.List Name Lib.FileInfo
    , _fileImport :: FileImport
    }


type Event = ()


data FileImport = FileImport
    { _suggestions :: L.List Name Text
    , _nameEdit    :: E.Editor Text Name
    }


data Name
    = Inbox
    | Library
    | NameSuggestions
    | FileNameEdit
    deriving (Eq, Ord, Show)


makeLenses ''FileImport

makeLenses ''State


initState :: IO State
initState = do
    config <- Lib.getDefaultConfig
    libraryFileInfos <- Lib.listFiles (config ^. Config.libraryDir)
    inboxFileInfos <- Lib.listFiles (config ^. Config.inboxDir)
    let
        libraryList = L.list Library (Vec.fromList libraryFileInfos) 1
        inboxList = L.list Inbox (Vec.fromList inboxFileInfos) 1
        fileImportInit =
            FileImport
            { _suggestions = L.list NameSuggestions (Vec.fromList []) 1
            , _nameEdit = E.editor FileNameEdit Nothing ""
            }
    pure
        $ State
        { _focusRing = initFocus
        , _library = libraryList
        , _inbox = inboxList
        , _fileImport = fileImportInit
        }


initFocus :: F.FocusRing Name
initFocus = F.focusRing [Inbox, Library]


app :: App State () Name
app = App
    { appDraw = drawUI
    , appChooseCursor = appCursor
    , appHandleEvent = handleEvent
    , appStartEvent = pure
    , appAttrMap = const theMap
    }


theMap :: AttrMap
theMap = attrMap V.defAttr
    [ (L.listAttr, V.brightWhite `on` V.black)
    , (L.listSelectedAttr, V.black `on` V.white)
    , (L.listSelectedFocusedAttr, V.black `on` V.brightWhite)
    , (E.editAttr, V.brightWhite `on` V.blue)
    , (E.editFocusedAttr, V.black `on` V.yellow)
    , ("suggestionList", bg V.cyan)
    , ("fileNamePreview", V.brightWhite `on` V.green)
    ]


appCursor :: State -> [CursorLocation Name] -> Maybe (CursorLocation Name)
appCursor s c = F.focusRingCursor (^. focusRing) s c


drawUI :: State -> [Widget Name]
drawUI s =
    let
        focus = F.focusGetCurrent (s ^. focusRing)

        inboxWidget =
            L.renderList drawFileInfo (focus == Just Inbox) (s ^. inbox)

        libraryWidget =
            L.renderList drawFileInfo (focus == Just Library) (s ^. library)

        mainScreen =
            withBorderStyle BS.unicodeRounded
                $ B.borderWithLabel (str "PAPERBOY")
                $ libraryWidget <=> B.hBorder <=> inboxWidget

        importWidget =
            drawImportWidget s

        ui =
            case focus of
                Just NameSuggestions ->
                    [importWidget, mainScreen]

                Just FileNameEdit ->
                    [importWidget, mainScreen]

                _ ->
                    [mainScreen]
    in
        ui


handleEvent :: State -> BrickEvent Name Event -> EventM Name (Next State)
handleEvent s (VtyEvent e) =
    case e of
        V.EvKey (V.KChar 'c') [V.MCtrl] -> halt s

        V.EvKey (V.KChar '\t') [] ->
            continue $ s & focusRing %~ F.focusNext

        V.EvKey V.KEsc [] ->
            continue (s & focusRing .~ initFocus)

        _ ->
            let
                focus = F.focusGetCurrent (s ^. focusRing)
            in
            case focus of
                Just Inbox ->
                    handleInboxEvent s e

                Just NameSuggestions ->
                    handleImportScreenEvent s e

                Just FileNameEdit ->
                    handleImportScreenEvent s e

                _ ->
                    continue s
handleEvent s _ = continue s


handleInboxEvent :: State -> V.Event -> EventM Name (Next State)
handleInboxEvent s e =
    let
        importAction =
            case L.listSelectedElement (s ^. inbox) of
                Just (_, fileInfo) -> beginFileImport s fileInfo
                _                  -> continue s
    in
    case e of
        V.EvKey V.KEnter [] ->
            importAction

        V.EvKey (V.KChar ' ') [] ->
            importAction

        _ -> do
            newInbox <- L.handleListEvent e (s ^. inbox)
            continue (s & inbox .~ newInbox)


beginFileImport :: State -> Lib.FileInfo -> EventM Name (Next State)
beginFileImport s fileInfo = do
    config <- liftIO $ Lib.getDefaultConfig
    fileNameSuggestions <- liftIO $ Lib.fileNameSuggestions config (Lib._fileName fileInfo)

    let
        fileName :| sugg = fileNameSuggestions

        newFileNames =
            L.list NameSuggestions (Vec.fromList sugg) 1

        newState = s
            & focusRing .~ (F.focusRing [FileNameEdit, NameSuggestions])
            & (fileImport . suggestions) .~ newFileNames
            & (fileImport . nameEdit) .~ (E.editor FileNameEdit Nothing fileName)

    handleImportScreenEvent newState (V.EvKey V.KDown [])


handleImportScreenEvent :: State -> V.Event -> EventM Name (Next State)
handleImportScreenEvent s e =
    let focus = F.focusGetCurrent (s ^. focusRing)
    in
    case focus of
        Just NameSuggestions ->
            do
                suggestionList <- L.handleListEvent e (s ^. fileImport ^. suggestions)

                let
                    newSuggestion =
                        case L.listSelectedElement suggestionList of
                            Just (_, t) ->
                                E.editor FileNameEdit Nothing t

                            _ -> s ^. fileImport ^. nameEdit

                newEdit <- E.handleEditorEvent (V.EvKey V.KDown []) newSuggestion

                continue $  s
                    & (fileImport . suggestions .~ suggestionList)
                    & (fileImport . nameEdit .~ newEdit)

        Just FileNameEdit ->
            do
                continue =<< handleEventLensed s (fileImport . nameEdit) E.handleEditorEvent e

        _ -> continue s

--

drawFileInfo :: Bool -> Lib.FileInfo -> Widget Name
drawFileInfo _ fileInfo =
    let
        fileLabel =
            [ str (Lib._fileName fileInfo)
            , fill ' '
            , str (fmt (dateDashF $ Lib._modTime fileInfo))
            ]

        fileLabelWidget =
            BC.vLimit 1 $ BC.hBox fileLabel
    in
        fileLabelWidget


drawImportWidget :: State -> Widget Name
drawImportWidget s =
    C.centerLayer
        $ B.borderWithLabel (str "Import")
        $ padLeftRight 2 $ padTopBottom 1 $ hLimit 70 $ vLimit 20
        $ vBox
            [ str "new filename:"
            , B.hBorder
            , vLimit 1
                $ E.renderEditor
                    (str . T.unpack . T.unlines)
                    (F.focusGetCurrent (s ^. focusRing) == Just FileNameEdit)
                    (s ^. fileImport ^. nameEdit)
            , vLimit 1 (fill ' ')
            , str "suggestions:"
            , B.hBorder
            , vLimit 4 -- $ withAttr "suggestionList"
                $ L.renderList
                    (\_ t -> str (T.unpack t))
                    (F.focusGetCurrent (s ^. focusRing) == Just NameSuggestions)
                    (s ^. fileImport ^. suggestions)
            -- , B.hBorder
            -- , vLimit 1 (fill ' ')
            -- , str "filename preview:"
            -- , withAttr "fileNamePreview" $ str (fileNamePreview $ s ^. fileImport ^. nameEdit)
            , fill ' '
            , str
                "Spaces will be replaced with _ and file extension will be appended.\n\
                \- [Tab] to switch between editor and suggestions.\n\
                \- [Enter] to rename the file and move it to your library folder."
            -- , str "Ctrl-a: go to beginning of line\n\
            -- \Ctrl-e: go to end of line\n\
            -- \Ctrl-d, Del: delete character at cursor position\n\
            -- \Backspace: delete character prior to cursor position\n\
            -- \Ctrl-k: delete all from cursor to end of line\n\
            -- \Ctrl-u: delete all from cursor to beginning of line\n\
            -- \Arrow keys: move cursor\n\
            -- \Enter: break the current line at the cursor position"
            ]

fileNamePreview :: E.Editor Text Name -> String
fileNamePreview ed =
    E.getEditContents ed
        & T.unlines
        & T.unpack