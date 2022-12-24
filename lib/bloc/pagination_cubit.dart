import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

part 'pagination_state.dart';

class PaginationCubit extends Cubit<PaginationState> {
  PaginationCubit(
    this._queries,
    this._limit,
    this._startAfterDocumentByQuery, {
    this.isLive = false,
    this.includeMetadataChanges = false,
    this.options,
  }) : super(PaginationInitial());

  Map<Query, DocumentSnapshot?>? _lastDocumentByQuery;
  final int _limit;
  final List<Query> _queries;
  final Map<Query, DocumentSnapshot?>? _startAfterDocumentByQuery;
  final bool isLive;
  final bool includeMetadataChanges;
  final GetOptions? options;

  final _streams = <StreamSubscription<QuerySnapshot>>[];

  void filterPaginatedList(String searchTerm) {
    if (state is PaginationLoaded) {
      final loadedState = state as PaginationLoaded;
      final filteredListByQuery = <Query, List<DocumentSnapshot>>{};

      for (var querySnap in loadedState.documentSnapshotsByQuery.entries) {
        final filteredList = querySnap.value
            .where((document) => document
                .data()
                .toString()
                .toLowerCase()
                .contains(searchTerm.toLowerCase()))
            .toList();

        filteredListByQuery[querySnap.key] = filteredList;
      }

      emit(loadedState.copyWith(
        documentSnapshotsByQuery: filteredListByQuery,
        hasReachedEndByQuery: loadedState.hasReachedEndByQuery,
      ));
    }
  }

  void refreshPaginatedList() async {
    _lastDocumentByQuery = null;
    final localQueries = _getQueries();
    if (isLive) {
      final listener = localQueries.map((q) => q
              .snapshots(includeMetadataChanges: includeMetadataChanges)
              .listen((querySnapshot) {
            _emitPaginatedState(q, querySnapshot.docs);
          }));

      _streams.addAll(listener);
    } else {
      final queriesSnapshots =
          await Future.wait(localQueries.map((q) => q.get(options)));
      queriesSnapshots.asMap().forEach((index, querySnapshot) {
        _emitPaginatedState(localQueries.elementAt(index), querySnapshot.docs);
      });
    }
  }

  void fetchPaginatedList() {
    isLive ? _getLiveDocuments() : _getDocuments();
  }

  _getDocuments() async {
    final localQueries = _getQueries();
    try {
      if (state is PaginationInitial) {
        refreshPaginatedList();
      } else if (state is PaginationLoaded) {
        final loadedState = state as PaginationLoaded;
        if (loadedState.allQueriesHaveReachedEnd()) return;

        final documentSnapshots = loadedState.getAllDocs();

        // Run queries in parallel
        final queriesSnapshots =
            await Future.wait(localQueries.map((q) => q.get(options)));

        queriesSnapshots.asMap().forEach(
          (index, querySnapshot) {
            _emitPaginatedState(
              localQueries.elementAt(index),
              querySnapshot.docs,
              previousList: documentSnapshots as List<QueryDocumentSnapshot>,
            );
          },
        );
      }
    } on PlatformException catch (exception) {
      // ignore: avoid_print
      print(exception);
      rethrow;
    }
  }

  _getLiveDocuments() {
    final localQueries = _getQueries();
    if (state is PaginationInitial) {
      refreshPaginatedList();
    } else if (state is PaginationLoaded) {
      PaginationLoaded loadedState = state as PaginationLoaded;
      if (loadedState.allQueriesHaveReachedEnd()) return;

      final listeners = localQueries.map((q) => q
              .snapshots(includeMetadataChanges: includeMetadataChanges)
              .listen((querySnapshot) {
            loadedState = state as PaginationLoaded;

            final documentSnapshots = loadedState.getAllDocs();

            _emitPaginatedState(
              q,
              querySnapshot.docs,
              previousList: documentSnapshots as List<QueryDocumentSnapshot>,
            );
          }));

      // add all ? or make a map of list of streams?
      _streams.addAll(listeners);
    }
  }

  void _emitPaginatedState(
    Query query,
    List<QueryDocumentSnapshot> newList, {
    List<QueryDocumentSnapshot> previousList = const [],
  }) {
    _lastDocumentByQuery ??= <Query, DocumentSnapshot?>{};
    _lastDocumentByQuery![query] = newList.isNotEmpty ? newList.last : null;

    PaginationLoaded loadedState = state as PaginationLoaded;
    loadedState.hasReachedEndByQuery[query] = newList.isEmpty;
    loadedState.documentSnapshotsByQuery[query] =
        _mergeSnapshots(previousList, newList);

    emit(PaginationLoaded(
      documentSnapshotsByQuery: loadedState.documentSnapshotsByQuery,
      hasReachedEndByQuery: loadedState.hasReachedEndByQuery,
    ));
  }

  List<QueryDocumentSnapshot> _mergeSnapshots(
    List<QueryDocumentSnapshot> previousList,
    List<QueryDocumentSnapshot> newList,
  ) {
    final prevIds = previousList.map((prevSnapshot) => prevSnapshot.id).toSet();
    newList.retainWhere((newSnapshot) => prevIds.add(newSnapshot.id));
    return previousList + newList;
  }

  Iterable<Query<Object?>> _getQueries() {
    var localQueries = _queries.map((q) {
      var lastDocument = _lastDocumentByQuery?[q];
      var startAfterDocument = _startAfterDocumentByQuery?[q];

      var localQuery = (lastDocument != null)
          ? q.startAfterDocument(lastDocument)
          : startAfterDocument != null
              ? q.startAfterDocument(startAfterDocument)
              : q;

      localQuery.limit(_limit);
      return localQuery;
    });

    return localQueries;
  }

  void dispose() {
    for (var listener in _streams) {
      listener.cancel();
    }
  }
}
