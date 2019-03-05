import 'dart:async';
import 'dart:collection';

import 'package:flutter/widgets.dart';
import 'package:rxdart/rxdart.dart';

import 'package:graphql_flutter/src/graphql_client.dart';
import 'package:graphql_flutter/src/core/observable_query.dart';
import 'package:graphql_flutter/src/core/query_options.dart';
import 'package:graphql_flutter/src/core/query_result.dart';

import 'package:graphql_flutter/src/widgets/graphql_provider.dart';

typedef FetchMoreCallback = void Function(
    int page, Map<String, dynamic> variables);

typedef QueryBuilder = Widget Function(QueryResult result,
    {VoidCallback refetch, FetchMoreCallback fetchMore});

/// Builds a [Query] widget based on the a given set of [QueryOptions]
/// that streams [QueryResult]s into the [QueryBuilder].
class Query extends StatefulWidget {
  const Query({
    final Key key,
    @required this.options,
    @required this.builder,
  }) : super(key: key);

  final QueryOptions options;
  final QueryBuilder builder;

  @override
  QueryState createState() => QueryState();
}

class QueryState extends State<Query> {
  ObservableQuery observableQuery;
  QueryResult currentResult;
  LinkedHashMap<int, ObservableQuery> pageResults =
      LinkedHashMap<int, ObservableQuery>.from(<int, ObservableQuery>{});

  WatchQueryOptions get _options {
    FetchPolicy fetchPolicy = widget.options.fetchPolicy;

    if (fetchPolicy == FetchPolicy.cacheFirst) {
      fetchPolicy = FetchPolicy.cacheAndNetwork;
    }

    return WatchQueryOptions(
      document: widget.options.document,
      variables: widget.options.variables,
      fetchPolicy: fetchPolicy,
      errorPolicy: widget.options.errorPolicy,
      pollInterval: widget.options.pollInterval,
      fetchResults: true,
      context: widget.options.context,
    );
  }

  void _initQuery() {
    final GraphQLClient client = GraphQLProvider.of(context).value;
    assert(client != null);

    observableQuery?.close();
    observableQuery = client.watchQuery(_options);
  }

  void _refetch() async {
    pageResults =
        LinkedHashMap<int, ObservableQuery>.from(<int, ObservableQuery>{});
    observableQuery.sendLoading();
    observableQuery.fetchResults();
  }

  void _fetchMore(int page, Map<String, dynamic> variables) {
    final GraphQLClient client = GraphQLProvider.of(context).value;
    if (pageResults.containsKey(page)) {
      pageResults[page].close();
    }
    final WatchQueryOptions pageOptions = _options;
    pageOptions.variables = variables;
    pageResults[page] = client.watchQuery(pageOptions);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _initQuery();
  }

  @override
  void didUpdateWidget(Query oldWidget) {
    super.didUpdateWidget(oldWidget);

    // TODO @micimize - investigate why/if this was causing issues
    if (!observableQuery.options.areEqualTo(_options)) {
      _initQuery();
    }
  }

  @override
  void dispose() {
    observableQuery?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QueryResult>(
      initialData: QueryResult(
        loading: true,
      ),
      stream: pageResults.isEmpty
          ? observableQuery.stream
          : CombineLatestStream.list<QueryResult>(
              <Stream<QueryResult>>[observableQuery.stream]..addAll(
                  pageResults.values
                      .map((ObservableQuery query) => query.stream)
                      .toList(),
                ),
            ).map<QueryResult>((List<QueryResult> results) {
              final QueryResult mergedResult = QueryResult();
              for (QueryResult result in results) {
                if (result.loading == true) {
                  mergedResult.loading = result.loading;
                }
                if (result.errors != null) {
                  mergedResult.errors = result.errors;
                  break;
                }
                if (mergedResult.data == null && result.data != null) {
                  mergedResult.data = result.data;
                } else if (result.data != null) {
                  // merge pages together
                  mergedResult.data = widget.options
                      .fetchMoreMerge(mergedResult.data, result.data);
                }
                if (result.stale != null) {
                  mergedResult.stale = result.stale;
                  break;
                }
              }
              return mergedResult;
            }), //observableQuery.stream,
      builder: (
        BuildContext buildContext,
        AsyncSnapshot<QueryResult> snapshot,
      ) {
        /// when re-fetching or loading the next page of data, we don't want to
        /// loose previous data. So loading should be true but we still keep
        /// the data from before until that changes
        if (currentResult?.data != null) {
          currentResult = QueryResult(
            loading: snapshot.data?.loading,
            data: snapshot.data?.data ?? currentResult.data,
            errors: snapshot.data?.errors,
            stale: snapshot.data?.stale,
          );
        } else {
          currentResult = snapshot.data;
        }

        return widget?.builder(
          currentResult,
          refetch: _refetch,
          fetchMore: _fetchMore,
        );
      },
    );
  }
}
