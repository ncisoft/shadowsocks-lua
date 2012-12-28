#include <stdio.h>
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

/**
  * @param string data
  * @param string trans_table
  */
static int meth_str_translate(lua_State *L)
{
  size_t data_len, trans_len;
  const unsigned char *data = (const unsigned char *) luaL_checklstring(L, 1, &data_len);
  const unsigned char *trans = (const unsigned char *) luaL_checklstring(L, 2, &trans_len);
  unsigned char stack_buf[8192];
  unsigned char *p, *ptail, *phead;

  if (trans_len != 256)
    {
      lua_pushnil(L);
      return 1;
    }

  if (data_len <= sizeof(stack_buf))
    p = stack_buf;
  else
    p = (unsigned char *) lua_newuserdata(L, data_len);
  phead = p;
  ptail = p + data_len;
  while(p < ptail)
      *p++ = trans[ *data++ ];

  lua_pushlstring(L, phead, data_len); 
  return 1;
}

static const luaL_reg mdm_reg[] = {
    {"str_translate",   meth_str_translate},
    {NULL, NULL}
};

//LUALIB_API 
int luaopen_mdm (lua_State *L)
{
    luaL_register(L, "mdm", mdm_reg);
    return 1;
}

