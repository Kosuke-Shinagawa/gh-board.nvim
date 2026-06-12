local M = {}

M.LIST_PROJECTS = [[
  query ListProjects($login: String!, $first: Int!) {
    user(login: $login) {
      projectsV2(first: $first) {
        nodes {
          id
          number
          title
          url
          closed
        }
      }
    }
  }
]]

M.GET_BOARD = [[
  query GetBoard($projectId: ID!, $first: Int!) {
    node(id: $projectId) {
      ... on ProjectV2 {
        id
        title
        fields(first: 20) {
          nodes {
            ... on ProjectV2SingleSelectField {
              id
              name
              options {
                id
                name
                color
              }
            }
          }
        }
        items(first: $first) {
          nodes {
            id
            fieldValues(first: 10) {
              nodes {
                ... on ProjectV2ItemFieldSingleSelectValue {
                  optionId
                  field {
                    ... on ProjectV2SingleSelectField {
                      id
                      name
                    }
                  }
                }
              }
            }
            content {
              ... on DraftIssue {
                id
                title
                body
                assignees(first: 5) {
                  nodes { login }
                }
                createdAt
                updatedAt
              }
              ... on Issue {
                id
                number
                title
                body
                state
                url
                assignees(first: 5) {
                  nodes { login }
                }
                labels(first: 10) {
                  nodes { name color }
                }
                createdAt
                updatedAt
              }
              ... on PullRequest {
                id
                number
                title
                body
                state
                url
                assignees(first: 5) {
                  nodes { login }
                }
                labels(first: 10) {
                  nodes { name color }
                }
                createdAt
                updatedAt
              }
            }
          }
        }
      }
    }
  }
]]

M.CREATE_CARD = [[
  mutation CreateCard($projectId: ID!, $title: String!, $body: String) {
    addProjectV2DraftIssue(input: {
      projectId: $projectId
      title: $title
      body: $body
    }) {
      projectItem {
        id
      }
    }
  }
]]

M.UPDATE_DRAFT_ISSUE = [[
  mutation UpdateDraftIssue($draftIssueId: ID!, $title: String!, $body: String) {
    updateProjectV2DraftIssue(input: {
      draftIssueId: $draftIssueId
      title: $title
      body: $body
    }) {
      draftIssue {
        id
        title
        body
      }
    }
  }
]]

M.UPDATE_ISSUE = [[
  mutation UpdateIssue($issueId: ID!, $title: String!, $body: String) {
    updateIssue(input: {
      id: $issueId
      title: $title
      body: $body
    }) {
      issue {
        id
        title
        body
      }
    }
  }
]]

M.MOVE_CARD = [[
  mutation MoveCard(
    $projectId: ID!
    $itemId: ID!
    $fieldId: ID!
    $optionId: String!
  ) {
    updateProjectV2ItemFieldValue(input: {
      projectId: $projectId
      itemId: $itemId
      fieldId: $fieldId
      value: { singleSelectOptionId: $optionId }
    }) {
      projectV2Item {
        id
      }
    }
  }
]]

M.DELETE_CARD = [[
  mutation DeleteCard($projectId: ID!, $itemId: ID!) {
    deleteProjectV2Item(input: {
      projectId: $projectId
      itemId: $itemId
    }) {
      deletedItemId
    }
  }
]]

return M
