part of 'pagination_cubit.dart';

@immutable
abstract class PaginationState {}

class PaginationInitial extends PaginationState {}

class PaginationError extends PaginationState {
  final Exception error;
  PaginationError({required this.error});

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PaginationError && other.error == error;
  }

  @override
  int get hashCode => error.hashCode;
}

class PaginationLoaded extends PaginationState {
  PaginationLoaded({
    required this.documentSnapshotsByQuery,
    required this.hasReachedEndByQuery,
  });

  final Map<Query, bool> hasReachedEndByQuery;
  final Map<Query, List<DocumentSnapshot>> documentSnapshotsByQuery;

  List<DocumentSnapshot> getAllDocs() {
    return documentSnapshotsByQuery.values.fold<List<DocumentSnapshot>>([],
        (allDocs, currentList) {
      allDocs.addAll(currentList);
      return allDocs;
    });
  }

  bool allQueriesHaveReachedEnd() {
    return hasReachedEndByQuery.values.every((hasReachedEnd) => hasReachedEnd);
  }

  PaginationLoaded copyWith({
    Map<Query, bool>? hasReachedEndByQuery,
    Map<Query, List<DocumentSnapshot>>? documentSnapshotsByQuery,
  }) {
    return PaginationLoaded(
      hasReachedEndByQuery: hasReachedEndByQuery ?? this.hasReachedEndByQuery,
      documentSnapshotsByQuery:
          documentSnapshotsByQuery ?? this.documentSnapshotsByQuery,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    if (other is PaginationLoaded) {
      // To be equal every "query & snapshot" pair must match
      bool everyQuerySnapshotMatches =
          other.documentSnapshotsByQuery.entries.every((querySnap) {
        return listEquals(
            querySnap.value, documentSnapshotsByQuery[querySnap.key]);
      });

      // To be equal every "query & end" pair must match
      bool everyQueryEndMatches =
          other.hasReachedEndByQuery.entries.every((queryEnd) {
        return queryEnd.value == hasReachedEndByQuery[queryEnd.key];
      });

      return everyQueryEndMatches && everyQuerySnapshotMatches;
    }
    return false;
  }

  @override
  int get hashCode =>
      hasReachedEndByQuery.hashCode ^ documentSnapshotsByQuery.hashCode;
}
