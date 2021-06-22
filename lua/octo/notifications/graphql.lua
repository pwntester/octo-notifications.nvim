local M = {}

M.inbox_query =
[[
query {
  viewer {
    notificationThreads(first: 100, query: "%s") {
      totalCount
      nodes {
        id
        threadType
        title
        isUnread
        unreadItemsCount
        lastUpdatedAt
        subscriptionStatus
        summaryItemBody
        isArchived
        isSaved
        reason
        url
      }
    }
  }
}
]]

M.notification_list_query =
  [[
query NotificationList {
  viewer {
    notificationFilters(first: 50) {
      nodes {
        ...NotificationListItem
      }
    }
    inbox: notificationThreads(filterBy: {statuses: UNREAD}) {
      totalCount
    }
    notificationListsWithThreadCount(first: 50, statuses: [UNREAD, READ]) {
      nodes {
        unreadCount
        list {
          ... on Repository {
            id
            nameWithOwner
            owner {
              login
            }
          }
        }
      }
    }
  }
}
fragment NotificationListItem on NotificationFilter {
  id
  name
  unreadCount
  queryString
}
]]

M.mark_as_read_mutation =
[[
mutation MarkNotificationsAsRead {
  markNotificationsAsRead(input: { ids: "%s"}) {
    success
  }
}
]]

M.mark_as_unread_mutation =
[[
mutation MarkNotificationAsUnread {
  markNotificationAsUnread(input: { id: "%s"}) {
    success
  }
}
]]

M.mark_as_done_mutation =
[[
mutation MarkNotificationAsDone {
  markNotificationAsDone(input:{id: "%s"}) {
    success
  }
}
]]

M.mark_as_saved_mutation =
[[
mutation MarkNotificationAsSaved {
  createSavedNotificationThread(input: { id: "%s"}) {
    success
  }
}
]]
return M
