const String readRepositories = r'''
query ReadRepositories($nRepositories: Int!, $after: String) {
  viewer {
    repositories(first: $nRepositories, after: $after) {
      totalCount
      edges {
        cursor
        node {
          __typename
          id
          name
          viewerHasStarred
        }
      }
    }
  }
}
''';
