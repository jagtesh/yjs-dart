/// Yjs Dart - A pure Dart translation of the Yjs CRDT library.
///
/// Mirrors: yjs/src/index.js (v14.0.0-22)
library yjs_dart;

// Core types
export 'src/utils/doc.dart' show Doc, DocOpts, generateNewClientId;
export 'src/utils/transaction.dart' show Transaction, transact;
export 'src/y_type.dart' show YType, AbstractType, YArray, YMap, YText, YXmlFragment;
export 'src/utils/y_event.dart' show YEvent;

// Structs
export 'src/structs/item.dart' show Item, AbstractContent;
export 'src/structs/abstract_struct.dart' show AbstractStruct;
export 'src/structs/gc.dart' show GC, structGCRefNumber;
export 'src/structs/skip.dart' show Skip, structSkipRefNumber;
export 'src/structs/content.dart'
    show
        ContentAny,
        ContentBinary,
        ContentDeleted,
        ContentDoc,
        ContentEmbed,
        ContentFormat,
        ContentJSON,
        ContentString,
        ContentType;

// ID utilities
export 'src/utils/id.dart' show ID, createID, compareIDs, writeID, readID;

// IdSet / IdMap
export 'src/utils/id_set.dart'
    show
        IdSet,
        IdRange,
        createIdSet,
        equalIdSets,
        mergeIdSets,
        diffIdSet,
        insertIntoIdSet;
export 'src/utils/id_map.dart'
    show IdMap, createIdMap, insertIntoIdMap, mergeIdMaps, filterIdMap;

// Relative positions
export 'src/utils/relative_position.dart'
    show
        RelativePosition,
        AbsolutePosition,
        createRelativePositionFromTypeIndex,
        createRelativePositionFromJSON,
        createAbsolutePositionFromRelativePosition,
        compareRelativePositions,
        relativePositionToJSON;

// Snapshots
export 'src/utils/snapshot.dart'
    show
        Snapshot,
        createSnapshot,
        snapshot,
        emptySnapshot,
        equalSnapshots,
        snapshotContainsUpdate;

// Struct store
export 'src/utils/struct_store.dart'
    show
        StructStore,
        addStructToStore,
        getStateVector,
        getState,
        findIndexSS,
        getItem,
        createDeleteSetFromStructStore,
        integrityCheck;

// Struct set
export 'src/utils/struct_set.dart'
    show
        StructSet,
        addStructToIdSet,
        createInsertSetFromStructStore,
        iterateStructsByIdSet;

// Encoders / Decoders
export 'src/utils/update_encoder.dart'
    show
        UpdateEncoderV1,
        UpdateEncoderV2,
        IdSetEncoderV1,
        IdSetEncoderV2,
        AbstractUpdateEncoder;
export 'src/utils/update_decoder.dart'
    show
        UpdateDecoderV1,
        UpdateDecoderV2,
        IdSetDecoderV1,
        IdSetDecoderV2,
        AbstractUpdateDecoder;

// Event handling
export 'src/utils/event_handler.dart'
    show
        EventHandler,
        createEventHandler,
        addEventHandlerListener,
        removeEventHandlerListener,
        removeAllEventHandlerListeners,
        callEventHandlerListeners;

// UndoManager
export 'src/utils/undo_manager.dart' show UndoManager, UndoManagerOpts;

// Utilities
export 'src/utils/is_parent_of.dart' show isParentOf;
export 'src/utils/logging.dart' show logType;
export 'src/utils/meta.dart' show yjsVersion;
export 'src/utils/delta_helpers.dart' show diffDocsToDelta;

// Updates (encoding/decoding)
export 'src/utils/updates.dart'
    show
        applyUpdate,
        applyUpdateV2,
        encodeStateAsUpdate,
        encodeStateAsUpdateV2,
        encodeStateVector,
        encodeStateVectorV2,
        encodeStateVectorFromUpdate,
        encodeStateVectorFromUpdateV2;

// Protocols
export 'src/protocols/auth.dart'
    show writePermissionDenied, readAuthMessage, messagePermissionDenied;
export 'src/protocols/awareness.dart'
    show
        Awareness,
        encodeAwarenessUpdate,
        applyAwarenessUpdate,
        removeAwarenessStates,
        modifyAwarenessUpdate;
export 'src/protocols/sync.dart'
    show
        writeSyncStep1,
        writeSyncStep2,
        readSyncStep1,
        readSyncStep2,
        writeUpdate,
        readUpdate,
        readSyncMessage,
        messageSyncStep1,
        messageSyncStep2,
        messageYjsUpdate;

// Lib0
export 'src/lib0/observable.dart' show Observable;
export 'src/lib0/encoding.dart'
    show
        Encoder,
        createEncoder,
        toUint8Array,
        writeVarUint,
        writeVarString,
        writeVarUint8Array;
export 'src/lib0/decoding.dart'
    show
        Decoder,
        createDecoder,
        readVarUint,
        readVarInt,
        readVarString,
        readVarUint8Array,
        hasContent,
        clone;
