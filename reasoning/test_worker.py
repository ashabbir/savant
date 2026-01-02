"""
Tests for Redis-based reasoning worker
"""
import pytest
import json
import time
from unittest.mock import Mock, patch, MagicMock
from reasoning.worker import process_job


class MockRedis:
    """Mock Redis client for testing"""
    def __init__(self):
        self.data = {}
        self.lists = {}
        
    def rpush(self, key, value):
        if key not in self.lists:
            self.lists[key] = []
        self.lists[key].append(value)
        return len(self.lists[key])
    
    def lpush(self, key, value):
        if key not in self.lists:
            self.lists[key] = []
        self.lists[key].insert(0, value)
        return len(self.lists[key])
    
    def ltrim(self, key, start, stop):
        if key in self.lists:
            self.lists[key] = self.lists[key][start:stop+1]
    
    def sadd(self, key, *values):
        if key not in self.data:
            self.data[key] = set()
        for v in values:
            self.data[key].add(v)
        return len(values)
    
    def srem(self, key, *values):
        if key in self.data:
            for v in values:
                self.data[key].discard(v)
        return len(values)
    
    def smembers(self, key):
        return self.data.get(key, set())


@pytest.fixture
def mock_redis():
    return MockRedis()


@pytest.fixture
def mock_api_module():
    """Mock the api module"""
    with patch('reasoning.worker.api_mod') as mock_api:
        # Mock AgentIntentRequest
        mock_api.AgentIntentRequest = Mock
        
        # Mock _compute_intent_sync
        mock_api._compute_intent_sync = Mock(return_value={
            'status': 'ok',
            'intent_id': 'test-123',
            'tool_name': 'context.fts_search',
            'tool_args': {'query': 'test'},
            'reasoning': 'test reasoning',
            'finish': False,
            'final_text': None,
            'trace': []
        })
        
        yield mock_api


def test_process_job_success(mock_redis, mock_api_module):
    """Test successful job processing"""
    job_data = {
        'job_id': 'test-job-1',
        'payload': {
            'session_id': 's1',
            'persona': {},
            'goal_text': 'test goal',
            'history': []
        }
    }
    
    process_job(mock_redis, json.dumps(job_data))
    
    # Verify job was added to running set
    assert 'test-job-1' in mock_redis.smembers('savant:jobs:running')
    
    # Verify _compute_intent_sync was called
    assert mock_api_module._compute_intent_sync.called
    
    # Verify completed job was logged
    assert 'savant:jobs:completed' in mock_redis.lists
    completed = json.loads(mock_redis.lists['savant:jobs:completed'][0])
    assert completed['job_id'] == 'test-job-1'
    assert completed['status'] == 'ok'


def test_process_job_with_callback(mock_redis, mock_api_module):
    """Test job processing with callback URL"""
    job_data = {
        'job_id': 'test-job-2',
        'callback_url': 'http://localhost/callback',
        'payload': {
            'session_id': 's2',
            'persona': {},
            'goal_text': 'test with callback'
        }
    }
    
    with patch('requests.post') as mock_post:
        mock_post.return_value.status_code = 200
        
        process_job(mock_redis, json.dumps(job_data))
        
        # Verify callback was called
        assert mock_post.called
        call_args = mock_post.call_args
        assert call_args[0][0] == 'http://localhost/callback'
        
        # Verify payload contains result
        payload = call_args[1]['json']
        assert payload['job_id'] == 'test-job-2'
        assert payload['status'] == 'ok'


def test_process_job_error_handling(mock_redis, mock_api_module):
    """Test job processing with error"""
    # Make _compute_intent_sync raise an exception
    mock_api_module._compute_intent_sync.side_effect = Exception('Test error')
    
    job_data = {
        'job_id': 'test-job-3',
        'payload': {
            'session_id': 's3',
            'persona': {},
            'goal_text': 'test error'
        }
    }
    
    process_job(mock_redis, json.dumps(job_data))
    
    # Verify failed job was logged
    assert 'savant:jobs:failed' in mock_redis.lists
    failed = json.loads(mock_redis.lists['savant:jobs:failed'][0])
    assert failed['job_id'] == 'test-job-3'
    assert 'Test error' in failed['error']


def test_process_job_removes_from_running_set(mock_redis, mock_api_module):
    """Test that job is removed from running set after completion"""
    job_data = {
        'job_id': 'test-job-4',
        'payload': {
            'session_id': 's4',
            'persona': {},
            'goal_text': 'test cleanup'
        }
    }
    
    process_job(mock_redis, json.dumps(job_data))
    
    # Verify job was removed from running set
    assert 'test-job-4' not in mock_redis.smembers('savant:jobs:running')


def test_process_job_stores_result_for_sync_polling(mock_redis, mock_api_module):
    """Test that result is stored in Redis for synchronous polling"""
    job_data = {
        'job_id': 'test-job-5',
        'payload': {
            'session_id': 's5',
            'persona': {},
            'goal_text': 'test sync result'
        }
    }
    
    # Mock rpush to capture result storage
    original_rpush = mock_redis.rpush
    result_key = None
    result_value = None
    
    def capture_rpush(key, value):
        nonlocal result_key, result_value
        if key.startswith('savant:result:'):
            result_key = key
            result_value = value
        return original_rpush(key, value)
    
    mock_redis.rpush = capture_rpush
    
    process_job(mock_redis, json.dumps(job_data))
    
    # Verify result was stored
    assert result_key == 'savant:result:test-job-5'
    assert result_value is not None
    
    result = json.loads(result_value)
    assert result['status'] == 'ok'
    assert result['intent_id'] == 'test-123'


def test_process_job_invalid_json(mock_redis, mock_api_module):
    """Test handling of invalid JSON in job data"""
    process_job(mock_redis, "invalid json{")
    
    # Should log to failed jobs
    assert 'savant:jobs:failed' in mock_redis.lists
