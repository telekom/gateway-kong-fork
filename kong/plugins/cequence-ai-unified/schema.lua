-- Unauthorized copying of this file, via any medium is strictly prohibited
--
-- Proprietary and confidential
--
-- Shailesh Goel, July 2023
--

local typedefs = require "kong.db.schema.typedefs"

return {
  name = "cequence-ai-unified",
  fields = {
    {
      consumer = typedefs.no_consumer
    },
    {
      protocols = typedefs.protocols_http
    },
    {
      config = {
        type = "record",
        fields = {
          {
            auth_domain = {
              type = "string",
              required = true,
            },
          },
          {
            edge_domain = {
              type = "string",
              required = true,
            },
          },
          {
            client_id = {
              type = "string",
              required = true,
            },
          },
          {
            realm = {
              type = "string",
              required = true,
            },
          },
          {
            client_secret = {
              type = "string",
              required = true,
            },
          },
          {
            batch_processing_enabled = {
              type = "boolean",
              required = true,
              default = true,
            },
          },
          {
            max_batch_size = {
              type = "number",
              default = 250,
            },
          },
          {
            retry_count_pre_v_3_3x = { 
              type = "number",
              default = 7,
            },
          },
          {
            process_delay_pre_v_3_3x = {
              type = "number",
              default = 5,
            },
          },
          {
            flush_timeout_pre_v_3_3x = {
              type = "number",
              default = 1,
            },
          },
          {
            max_queued_batches_pre_v_3_3x = {
              type = "number",
              default = 500,
            },
          },
          {
            max_coalescing_delay_post_v_3_3x = {
              type = "number",
              default = 5,
            },
          },
          {
            max_entries_post_v_3_3x = {
              type = "number",
              default = 10000,
            },
          },
          {
            initial_retry_delay_post_v_3_3x = {
              type = "number",
              default = 1,
            },
          },
          {
            max_retry_time_post_v_3_3x = {
              type = "number",
              default = 120,
            },
          },
          {
            max_retry_delay_post_v_3_3x = {
              type = "number",
              default = 60,
            },
          },
        },
      },
    },
  },
}
