local utils = require "kong.tools.utils"
local DaoError = require "kong.dao.error"
local constants = require "kong.constants"

local function load_value_schema(plugin_t)
  if plugin_t.name then
    local loaded, plugin_schema = utils.load_module_if_exists("kong.plugins."..plugin_t.name..".schema")
    if loaded then
      return plugin_schema
    else
      return nil, "Plugin \""..(plugin_t.name and plugin_t.name or "").."\" not found"
    end
  end
end

return {
  name = "Plugin configuration",
  primary_key = {"id"},
  clustering_key = {"name"},
  fields = {
    id = { type = "id", dao_insert_value = true },
    created_at = { type = "timestamp", dao_insert_value = true },
    api_id = { type = "id", required = true, foreign = "apis:id", queryable = true },
    consumer_id = { type = "id", foreign = "consumers:id", queryable = true, default = constants.DATABASE_NULL_ID },
    name = { type = "string", required = true, immutable = true, queryable = true },
    value = { type = "table", schema = load_value_schema },
    enabled = { type = "boolean", default = true }
  },
  on_insert = function(plugin_t, dao, schema)
    -- Load the value schema
    local value_schema, err = schema.fields.value.schema(plugin_t)
    if err then
      return false, err
    end

    -- Check if the schema has a `no_consumer` field
    if value_schema.no_consumer and plugin_t.consumer_id ~= nil and plugin_t.consumer_id ~= constants.DATABASE_NULL_ID then
      return false, DaoError("No consumer can be configured for that plugin", constants.DATABASE_ERROR_TYPES.SCHEMA)
    end

    -- Invoke on_insert() on the plugin
    if value_schema.on_insert and type(value_schema.on_insert) == "function" then
      local valid, err = value_schema.on_insert(plugin_t.value or {}, dao, value_schema)
      if not valid or err then
        return false, DaoError(err, constants.DATABASE_ERROR_TYPES.SCHEMA)
      end
    end

    local res, err = dao.plugins_configurations:find_by_keys({
      name = plugin_t.name,
      api_id = plugin_t.api_id,
      consumer_id = plugin_t.consumer_id
    })

    if err then
      return nil, DaoError(err, constants.DATABASE_ERROR_TYPES.DATABASE)
    end

    if res and #res > 0 then
      return false, DaoError("Plugin configuration already exists", constants.DATABASE_ERROR_TYPES.UNIQUE)
    else
      return true
    end
  end
}
