/*
 * Copyright 2014 MongoDB, Inc.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "CLibMongoC_bson-prelude.h"


#ifndef BSON_CONTEXT_PRIVATE_H
#define BSON_CONTEXT_PRIVATE_H


#include "CLibMongoC_bson-context.h"
#include "common-thread-private.h"


BSON_BEGIN_DECLS


struct _bson_context_t {
   /* flags are defined in bson_context_flags_t */
   int flags;
   int32_t seq32;
   int64_t seq64;
   uint8_t rand[5];
   uint16_t pid;

   void (*oid_set_seq32) (bson_context_t *context, bson_oid_t *oid);
   void (*oid_set_seq64) (bson_context_t *context, bson_oid_t *oid);

   /* this function pointer allows us to mock gethostname for testing. */
   void (*gethostname) (char *out);
};

void
_bson_context_set_oid_rand (bson_context_t *context, bson_oid_t *oid);


BSON_END_DECLS


#endif /* BSON_CONTEXT_PRIVATE_H */
