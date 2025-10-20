#!/usr/bin/env ruby
#
# Purpose: Implement Jira operations via REST v3.
#
# Contains all HTTP interactions and response shaping for searching, getting,
# creating, updating, transitioning, and deleting issues, along with comments,
# attachments, assignments, links, and metadata listing.

require_relative 'client'

module Savant
  module Jira
    class Ops
      def initialize(client)
        @c = client
      end

      def search(jql:, limit: 10, start_at: 0, fields: %w[key summary status assignee updated])
        body = { jql: jql, maxResults: limit.to_i, startAt: start_at.to_i, fields: fields }
        res = @c.post('/rest/api/3/search', body.to_json)
        (res['issues'] || []).map do |it|
          f = it['fields'] || {}
          { key: it['key'], summary: f['summary'], status: f.dig('status','name'), assignee: f.dig('assignee','displayName'), updated: f['updated'], url: "#{@c.base_url}/browse/#{it['key']}" }
        end
      end

      def get_issue(key:, fields: nil)
        params = {}
        params[:fields] = Array(fields).join(',') if fields && !fields.empty?
        @c.get("/rest/api/3/issue/#{key}", params)
      end

      def create_issue(projectKey:, summary:, issuetype:, description: nil, fields: {})
        payload = { fields: fields.merge({'project'=>{'key'=>projectKey}, 'summary'=>summary, 'issuetype'=>{'name'=>issuetype}}.tap{ |h| h['description']=description if description }) }
        res = @c.post('/rest/api/3/issue', payload.to_json)
        { key: res['key'], url: "#{@c.base_url}/browse/#{res['key']}" }
      end

      def update_issue(key:, fields: {})
        @c.put("/rest/api/3/issue/#{key}", { fields: fields }.to_json)
        { key: key, updated: true }
      end

      def list_transitions(key:)
        res = @c.get("/rest/api/3/issue/#{key}/transitions")
        res['transitions'] || []
      end

      def transition_issue(key:, transitionName: nil, transitionId: nil)
        if transitionId.to_s.empty?
          found = list_transitions(key: key).find { |t| t['name'].casecmp?(transitionName.to_s) }
          raise 'transition not found' unless found
          transitionId = found['id']
        end
        @c.post("/rest/api/3/issue/#{key}/transitions", { transition: { id: transitionId.to_s } }.to_json)
        { key: key, transitioned: true }
      end

      def add_comment(key:, body:)
        res = @c.post("/rest/api/3/issue/#{key}/comment", { body: body }.to_json)
        { id: res['id'], created: res['created'] }
      end

      def delete_comment(key:, id:)
        @c.delete("/rest/api/3/issue/#{key}/comment/#{id}")
        { deleted: true }
      end

      def assign_issue(key:, accountId: nil, name: nil)
        body = accountId ? { accountId: accountId } : { name: name }
        @c.put("/rest/api/3/issue/#{key}/assignee", body.to_json)
        { key: key, assignee: accountId || name }
      end

      def link_issues(inwardKey:, outwardKey:, linkType:)
        @c.post('/rest/api/3/issueLink', { type: { name: linkType }, inwardIssue: { key: inwardKey }, outwardIssue: { key: outwardKey } }.to_json)
        { created: true }
      end

      def download_attachments(key:)
        issue = get_issue(key: key, fields: ['attachment'])
        atts = (issue.dig('fields','attachment') || [])
        files = []
        dir = Dir.mktmpdir('jira_atts')
        atts.each do |att|
          res = @c.raw_get_url(att['content'])
          path = File.join(dir, att['filename'])
          File.binwrite(path, res.body)
          files << { id: att['id'], filename: att['filename'], path: path }
        end
        { count: files.length, files: files }
      end

      def add_attachment(key:, filePath:)
        file = File.binread(filePath)
        boundary = "----SavantBoundary#{rand(1_000_000)}"
        body = "--#{boundary}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"#{File.basename(filePath)}\"\r\nContent-Type: application/octet-stream\r\n\r\n" + file + "\r\n--#{boundary}--\r\n"
        res = @c.multipart_post("/rest/api/3/issue/#{key}/attachments", body, boundary)
        item = JSON.parse(res.body).first
        { id: item['id'], filename: item['filename'] }
      end

      def bulk_create_issues(issues: [])
        payload = { issueUpdates: issues.map { |i| { fields: (i['fields'] || {}).merge({ 'project'=>{'key'=>i['projectKey']}, 'summary'=>i['summary'], 'issuetype'=>{'name'=>i['issuetype']} }.tap{ |h| h['description']=i['description'] if i['description'] }) } } }
        res = @c.post('/rest/api/3/issue/bulk', payload.to_json)
        { keys: (res.dig('issues') || []).map { |x| x['key'] } }
      end

      def list_projects
        res = @c.get('/rest/api/3/project/search')
        res['values'] || []
      end

      def list_fields
        @c.get('/rest/api/3/field')
      end

      def list_statuses(projectKey: nil)
        if projectKey
          @c.get("/rest/api/3/project/#{projectKey}/statuses")
        else
          @c.get('/rest/api/3/status')
        end
      end
    end
  end
end
