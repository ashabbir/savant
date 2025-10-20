require 'json'
require_relative 'engine'

module Savant
  module Jira
    module Tools
      module_function

      def specs
        [
          { name: 'jira_search', description: 'Run a Jira JQL search', inputSchema: { type: 'object', properties: { jql: { type: 'string' }, limit: { type: 'integer', minimum: 1, maximum: 100 }, start_at: { type: 'integer', minimum: 0 } }, required: ['jql'] } },
          { name: 'jira_get_issue', description: 'Get a Jira issue (v3)', inputSchema: { type: 'object', properties: { key: { type: 'string' }, fields: { type: 'array', items: { type: 'string' } } }, required: ['key'] } },
          { name: 'jira_create_issue', description: 'Create a Jira issue (v3)', inputSchema: { type: 'object', properties: { projectKey: { type: 'string' }, summary: { type: 'string' }, issuetype: { type: 'string' }, description: { type: 'string' }, fields: { type: 'object' } }, required: ['projectKey','summary','issuetype'] } },
          { name: 'jira_update_issue', description: 'Update a Jira issue (v3)', inputSchema: { type: 'object', properties: { key: { type: 'string' }, fields: { type: 'object' } }, required: ['key','fields'] } },
          { name: 'jira_transition_issue', description: 'Transition a Jira issue (v3)', inputSchema: { type: 'object', properties: { key: { type: 'string' }, transitionName: { type: 'string' }, transitionId: { type: 'string' } }, required: ['key'] } },
          { name: 'jira_add_comment', description: 'Add a comment to an issue (v3)', inputSchema: { type: 'object', properties: { key: { type: 'string' }, body: { type: 'string' } }, required: ['key','body'] } },
          { name: 'jira_delete_comment', description: 'Delete a comment (v3)', inputSchema: { type: 'object', properties: { key: { type: 'string' }, id: { type: 'string' } }, required: ['key','id'] } },
          { name: 'jira_download_attachments', description: 'Download issue attachments (v3)', inputSchema: { type: 'object', properties: { key: { type: 'string' } }, required: ['key'] } },
          { name: 'jira_add_attachment', description: 'Upload attachment to issue (v3)', inputSchema: { type: 'object', properties: { key: { type: 'string' }, filePath: { type: 'string' } }, required: ['key','filePath'] } },
          { name: 'jira_add_watcher_to_issue', description: 'Add watcher (v3)', inputSchema: { type: 'object', properties: { key: { type: 'string' }, accountId: { type: 'string' } }, required: ['key','accountId'] } },
          { name: 'jira_assign_issue', description: 'Assign issue (v3)', inputSchema: { type: 'object', properties: { key: { type: 'string' }, accountId: { type: 'string' }, name: { type: 'string' } }, required: ['key'] } },
          { name: 'jira_bulk_create_issues', description: 'Bulk create issues (v3)', inputSchema: { type: 'object', properties: { issues: { type: 'array', items: { type: 'object' } } }, required: ['issues'] } },
          { name: 'jira_delete_issue', description: 'Delete issue (v3)', inputSchema: { type: 'object', properties: { key: { type: 'string' } }, required: ['key'] } },
          { name: 'jira_link_issues', description: 'Link two issues (v3)', inputSchema: { type: 'object', properties: { inwardKey: { type: 'string' }, outwardKey: { type: 'string' }, linkType: { type: 'string' } }, required: ['inwardKey','outwardKey','linkType'] } },
          { name: 'jira_self', description: 'Verify Jira credentials', inputSchema: { type: 'object', properties: {} } }
        ]
      end

      def dispatch(engine, name, args)
        case name
        when 'jira_search'
          engine.search(jql: args['jql'].to_s, limit: (args['limit'] || 10).to_i, start_at: (args['start_at'] || 0).to_i)
        when 'jira_get_issue'
          engine.get_issue(key: args['key'].to_s, fields: args['fields'])
        when 'jira_create_issue'
          engine.create_issue(projectKey: args['projectKey'], summary: args['summary'], issuetype: args['issuetype'], description: args['description'], fields: (args['fields'] || {}))
        when 'jira_update_issue'
          engine.update_issue(key: args['key'], fields: (args['fields'] || {}))
        when 'jira_transition_issue'
          engine.transition_issue(key: args['key'], transitionName: args['transitionName'], transitionId: args['transitionId'])
        when 'jira_add_comment'
          engine.add_comment(key: args['key'], body: args['body'])
        when 'jira_delete_comment'
          engine.delete_comment(key: args['key'], id: args['id'])
        when 'jira_download_attachments'
          engine.download_attachments(key: args['key'])
        when 'jira_add_attachment'
          engine.add_attachment(key: args['key'], filePath: args['filePath'])
        when 'jira_add_watcher_to_issue'
          # Jira API expects raw accountId string body
          client = engine.instance_variable_get(:@client)
          client.post("/rest/api/3/issue/#{args['key']}/watchers", args['accountId'].to_json)
          { added: true }
        when 'jira_assign_issue'
          engine.assign_issue(key: args['key'], accountId: args['accountId'], name: args['name'])
        when 'jira_bulk_create_issues'
          engine.bulk_create_issues(issues: args['issues'] || [])
        when 'jira_delete_issue'
          engine.delete_issue(key: args['key'])
        when 'jira_link_issues'
          engine.link_issues(inwardKey: args['inwardKey'], outwardKey: args['outwardKey'], linkType: args['linkType'])
        when 'jira_self'
          engine.self_test
        else
          raise 'Unknown Jira tool'
        end
      end
    end
  end
end

