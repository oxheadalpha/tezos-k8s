-- src/db-schema/versions.sql
-- Open Source License
-- Copyright (c) 2019-2020 Nomadic Labs <contact@nomadic-labs.com>
--
-- Permission is hereby granted, free of charge, to any person obtaining a
-- copy of this software and associated documentation files (the "Software"),
-- to deal in the Software without restriction, including without limitation
-- the rights to use, copy, modify, merge, publish, distribute, sublicense,
-- and/or sell copies of the Software, and to permit persons to whom the
-- Software is furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included
-- in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
-- THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
-- FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
-- DEALINGS IN THE SOFTWARE.

\set ON_ERROR_STOP on

SELECT 'versions.sql' as file;


DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_tables where tablename = 'block')
  AND NOT EXISTS (SELECT 1 FROM pg_tables where tablename = 'indexer_version') THEN
    raise 'You seem to be running a non compatible version of the indexer';
  END IF;
END
$$;

----------------------------------------------------------------------
-- VERSION HISTORY
----------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS indexer_version (
     version text primary key -- the current version
   , new_tables text not null -- the most recent version where new tables were introduced
   , new_columns text not null -- the most recent version where new columns were introduced
   , alter_types text not null -- the most recent version where some types were altered
   , build text -- placeholder for now
   , dev bool not null -- should be set to true, except for released versions
   , multicore bool not null
   , autoid SERIAL UNIQUE
);

do $$
begin
if (select count(*) from indexer_version where version < '9.0.0') = 0
then
  if (select count(*) from indexer_version where version >= '9.0.2') = 0
     AND
      (SELECT EXISTS (
        SELECT FROM information_schema.tables
        WHERE  table_schema = 'c'
        AND    table_name   = 'operation_alpha'
       ))
  then
    alter table c.operation_alpha alter COLUMN autoid set not null;
  end if;
  insert into indexer_version values (
     '9.0.5' -- version
   , '9.0.0' -- new_tables
   , '9.0.0' -- new_columns
   , '9.0.5' -- alter_types
   , '' -- build
   , false -- dev
   , false --SEQONLY
   ) on conflict (version) do
   update set multicore = false --SEQONLY
   ;
else
  raise 'You already have a non-compatible schema.';
End if;
end
$$;
-- src/db-schema/schemas.sql
-- Open Source License
-- Copyright (c) 2021 Nomadic Labs <contact@nomadic-labs.com>
--
-- Permission is hereby granted, free of charge, to any person obtaining a
-- copy of this software and associated documentation files (the "Software"),
-- to deal in the Software without restriction, including without limitation
-- the rights to use, copy, modify, merge, publish, distribute, sublicense,
-- and/or sell copies of the Software, and to permit persons to whom the
-- Software is furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included
-- in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
-- THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
-- FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
-- DEALINGS IN THE SOFTWARE.

SELECT 'schemas.sql' as file;

-- Note that although we use upper case for schema names in our code,
-- Postgres doesn't see them any differently than if they were in lower case.
-- Moreover, if you are using psql and want autocompletion, upper case may not work
-- and you may have to use lower case notation.
-- The upper case is used to facilitate refactoring when need be and reading.


-- Blockchain's core data
create schema if not exists C;

-- Insertion functions
create schema if not exists I;

-- Pre-Insertion functions (insertion of incomplete rows)
create schema if not exists H;

-- Update functions
create schema if not exists U;

-- Get functions
create schema if not exists G;

-- Mempool
create schema if not exists M;

-- Tokens
create schema if not exists T;

-- Bigmaps
create schema if not exists B;
-- src/db-schema/addresses.sql
-- Open Source License
-- Copyright (c) 2020 Nomadic Labs <contact@nomadic-labs.com>
--
-- Permission is hereby granted, free of charge, to any person obtaining a
-- copy of this software and associated documentation files (the "Software"),
-- to deal in the Software without restriction, including without limitation
-- the rights to use, copy, modify, merge, publish, distribute, sublicense,
-- and/or sell copies of the Software, and to permit persons to whom the
-- Software is furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included
-- in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
-- THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
-- FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
-- DEALINGS IN THE SOFTWARE.

-- Lines starting with --OPT may be automatically activated
-- Lines ending with --OPT may be automatically deactivated

SELECT 'addresses.sql' as file;

-- table of all existing addresses, so their storage can be factorized here

CREATE TABLE IF NOT EXISTS C.addresses (
 address char(36),
 address_id bigint not null unique,
 primary key(address)
);
CREATE INDEX IF NOT EXISTS addresses_autoid on C.addresses using btree (address_id);


CREATE OR REPLACE FUNCTION address_id(a char)
returns bigint
as $$
select address_id from C.addresses where address = a;
$$ language sql stable;


create or replace function I.address_aux(a char, id bigint)
returns bigint
as $$
insert into C.addresses values(a, id) on conflict do nothing returning address_id;
$$ language SQL;

CREATE OR REPLACE FUNCTION I.address(a char, id bigint)
returns bigint
as $$
DECLARE r bigint := null;
BEGIN
r := (select address_id from C.addresses where address = a);
if r is not null
then
  return r;
else
  r := (select I.address_aux(a, id));
  if r is null
  then
    r := (select address_id from C.addresses where address = a);
    if r is null then
      r := (select I.address_aux(a, -id));
    end if;
  else
    return r;
  end if;
  if r is null
  then
    r := (select address_id from C.addresses where address = a);
    if r is null then
      r := (select I.address_aux(a, -(id/100)+(random()*100)::bigint));
    end if;
  else
    return r;
  end if;
  if r is null
  then
    raise 'Failed to record address % % % %', a, r, (select address from c.addresses where address = a), (select address_id::text from c.addresses where address = a);
  else
    return r;
  end if;
end if;
END
$$ language plpgsql;




CREATE OR REPLACE FUNCTION address(id bigint)
returns char
as $$
select address from C.addresses where address_id = id;
$$ language sql stable;
-- src/db-schema/chain.sql
-- Open Source License
-- Copyright (c) 2019 Vincent Bernardoff <vb@luminar.eu.org>
-- Copyright (c) 2019-2021 Nomadic Labs <contact@nomadic-labs.com>
--
-- Permission is hereby granted, free of charge, to any person obtaining a
-- copy of this software and associated documentation files (the "Software"),
-- to deal in the Software without restriction, including without limitation
-- the rights to use, copy, modify, merge, publish, distribute, sublicense,
-- and/or sell copies of the Software, and to permit persons to whom the
-- Software is furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included
-- in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
-- THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
-- FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
-- DEALINGS IN THE SOFTWARE.

-----------------------------------------------------------------------------
-----------------------------------------------------------------------------
-- Lines starting with --OPT may be automatically activated
-- Lines ending with --OPT may be automatically deactivated
-----------------------------------------------------------------------------
-----------------------------------------------------------------------------
-- Naming conventions:
-- - for tables:
--   * use singular for names, use plural for column names that are arrays
--   * table 'proposals' is plural because what it contains is plural (it contains 'proposals' on each row)
-----------------------------------------------------------------------------
-----------------------------------------------------------------------------
-- Foreign keys:
-- They are declared in special comments starting with `--FKEY`, and must start the line.
--  --FKEY name_of_foreign_key ; name_of_table ; set, of, columns ; foreign_table_name(column_name) ; action
-- where action can be CASCADE or SET NULL
-- Refer to existing one for examples.
-----------------------------------------------------------------------------
-----------------------------------------------------------------------------

SELECT 'chain.sql' as file;

-----------------------------------------------------------------------------
-- Some logs about what happens while running the indexer

CREATE TABLE IF NOT EXISTS indexer_log (
   timestamp timestamp DEFAULT CURRENT_TIMESTAMP,
   version text not null default '',
   argv text not null default '',
   action text not null default '',
   primary key (timestamp, version, argv, action)
);
CREATE INDEX IF NOT EXISTS indexer_log_timestamp on indexer_log using btree(timestamp);

-----------------------------------------------------------------------------
-- storing the chain id

CREATE TABLE IF NOT EXISTS C.chain (
  hash char(15) primary key
);

CREATE TABLE IF NOT EXISTS C.block_hash (
  hash char(51) not null
, hash_id int UNIQUE not null
);
CREATE UNIQUE INDEX IF NOT EXISTS block_hash_hash_id on C.block_hash using btree (hash_id);
--PKEY block_hash_pkey; C.block_hash; hash --SEQONLY


-----------------------------------------------------------------------------
-- this table inlines blocks and block headers
-- see lib_base/block_header.mli

CREATE TABLE IF NOT EXISTS C.block (
  hash_id int not null unique,
  -- Block hash.
  -- 51 = 32 bytes hashes encoded in b58check + length of prefix "B"
  -- see lib_crypto/base58.ml
  level int not null,
  -- Height of the block, from the genesis block.
  proto int not null,
  -- Number of protocol changes since genesis modulo 256.
  predecessor_id int not null,
  -- Hash of the preceding block.
  timestamp timestamp not null,
  -- Timestamp at which the block is claimed to have been created.
  validation_passes smallint not null,
  -- Number of validation passes (also number of lists of operations).
  merkle_root char(53) not null,
  -- see [operations_hash]
  -- Hash of the list of lists (actually root hashes of merkle trees)
  -- of operations included in the block. There is one list of
  -- operations per validation pass.
  -- 53 = 32 bytes hashes encoded in b58 check + "LLo" prefix
  fitness varchar(64) not null,
  -- A sequence of sequences of unsigned bytes, ordered by length and
  -- then lexicographically. It represents the claimed fitness of the
  -- chain ending in this block.
  context_hash char(52) not null,
  -- Hash of the state of the context after application of this block.
  rejected bool not null default false -- AKA "uncle block" or "forked"
  -- if true, this block is not in the blockchain anymore
  -- if false, we're not sure! It might be rejected later...
  , indexing_depth smallint not null default 0 -- depth the indexer managed to index the block, 0 means there was an error
);
--PKEY block_pkey; C.block; hash_id, level --SEQONLY
--fkey block_predecessor_id_fkey ; C.block ; hash_id ; C.block_hash(hash_id) ; CASCADE --SEQONLY
--FKEY block_predecessor_id_fkey_s ; C.block ; predecessor_id ; C.block(hash_id) ; CASCADE --SEQONLY
CREATE INDEX IF NOT EXISTS block_rejected on C.block using btree (rejected); --SEQONLY
CREATE INDEX IF NOT EXISTS block_level    on C.block using btree (level); --SEQONLY
CREATE UNIQUE INDEX IF NOT EXISTS block_hash_id     on C.block using btree (hash_id);

CREATE OR REPLACE FUNCTION block_hash(id int) returns char as $$ select hash from C.block_hash where hash_id = id $$ language sql stable;

CREATE OR REPLACE FUNCTION block_hash_id(h char) returns int as $$ select hash_id from C.block_hash where hash = h $$ language sql stable;

--SELECT setval('C.block_hash_auto_hash_id_seq', coalesce((select level+1 from C.block order by level desc limit 1), 1), false);--SEQONLY

-----------------------------------------------------------------------------
-- operations seen from block-level, therefore non-protocol-specific information

CREATE TABLE IF NOT EXISTS C.operation (
  -- Note: an operation may point to a rejected block only if the
  -- operation itself was deleted from the chain.
  -- If the operation was included in a rejected block but then
  -- reinjected into another block, then this table contains the
  -- latest block_hash associated to that operation.
  -- Hypothesis: the latest write is always right.
  hash char(51) not null, -- operation hash
  block_hash_id int not null, -- char(51) not null, -- block hash
  hash_id bigint not null
);
--FKEY operation_block_hash_id_fkey; C.operation; block_hash_id; C.block(hash_id) ; CASCADE --SEQONLY
--PKEY operation_pkey; C.operation; hash_id --SEQONLY

CREATE INDEX IF NOT EXISTS operation_block on C.operation using btree (block_hash_id); --SEQONLY
CREATE INDEX IF NOT EXISTS operation_hash on C.operation using btree (hash); --SEQONLY
CREATE INDEX IF NOT EXISTS operation_hash_id on C.operation using btree (hash_id); --SEQONLY

CREATE OR REPLACE FUNCTION operation_hash(id bigint) returns char as $$ select hash from C.operation where hash_id = id $$ language sql stable;

CREATE OR REPLACE FUNCTION operation_hash_id(h char) returns bigint as $$ select hash_id from C.operation where hash = h $$ language sql stable;

-----------------------------------------------------------------------------
-- Index of protocol-specific contents of an operation
-- An "operation" at the "shell" level is a "set of operations" at the "protocol" level.
-- In the following table, "hash_id" refers to an operation at the shell level.
-- At the protocol level, a shell-level operation is a list of operations (the word "operation" has different meanings).
-- Inside protocol-level operations, there can be some additional "internal operations".
-- "Internal operations" (a.k.a. "internal manager operation") are operations that are at manager-operation-level.
-- An "internal operation", so far, for protocols 1 to 8, are only manager operations (inside manager operations).
-- There are differences between "manager operations" and "internal manager operations".
-- For instance, internal ones don't have data in manager_numbers, but are the only ones that have a "nonce" (which are integers).

CREATE TABLE IF NOT EXISTS C.operation_alpha (
  block_hash_id int not null,
  -- block hash id
  hash_id bigint not null,
  -- operation hash id
  id smallint not null,
  -- index of op in contents_list
  operation_kind smallint not null,
  -- from mezos/chain_db.ml
  -- see proto_alpha/operation_repr.ml
  -- (this would better be called "kind")
  -- type of operation alpha
  -- 0: Endorsement
  -- 1: Seed_nonce_revelation
  -- 2: double_endorsement_evidence
  -- 3: Double_baking_evidence
  -- 4: Activate_account
  -- 5: Proposals
  -- 6: Ballot
  -- 7: Manager_operation { operation = Reveal _ ; _ }
  -- 8: Manager_operation { operation = Transaction _ ; _ }
  -- 9: Manager_operation { operation = Origination _ ; _ }
  -- 10: Manager_operation { operation = Delegation _ ; _ }
  internal smallint not null,
  -- block hash
  autoid bigint not null UNIQUE -- counter id
);
--PKEY operation_alpha_pkey; C.operation_alpha; hash_id, id, internal, block_hash_id --SEQONLY
--FKEY operation_alpha_hash_fkey; C.operation_alpha; hash_id; C.operation(hash_id) ; CASCADE --SEQONLY
--FKEY operation_alpha_block_hash_fkey; C.operation_alpha; block_hash_id; C.block(hash_id) ; CASCADE --SEQONLY
CREATE INDEX IF NOT EXISTS operation_alpha_kind on C.operation_alpha using btree (operation_kind); --SEQONLY
CREATE INDEX IF NOT EXISTS operation_alpha_hash on C.operation_alpha using btree (hash_id); --SEQONLY
CREATE INDEX IF NOT EXISTS operation_alpha_block_hash on C.operation_alpha using btree (block_hash_id); --SEQONLY
CREATE UNIQUE INDEX IF NOT EXISTS operation_alpha_autoid on C.operation_alpha using btree (autoid);

CREATE OR REPLACE FUNCTION operation_alpha_autoid(ophid bigint, opid smallint, i smallint, bhid bigint)
RETURNS bigint
AS $$
SELECT autoid
FROM C.operation_alpha
WHERE (hash_id, id, internal, block_hash_id) = (ophid, opid, i, bhid);
$$ LANGUAGE SQL STABLE;

DROP FUNCTION IF EXISTS operation_hash_alpha(bigint) cascade;
CREATE OR REPLACE FUNCTION operation_hash_alpha(opaid bigint)
RETURNS TABLE(hash char) as $$
select o.hash from c.operation o, c.operation_alpha a where a.autoid = opaid and a.hash_id = o.hash_id
$$ LANGUAGE SQL STABLE;

DROP FUNCTION IF EXISTS operation_hash_id_alpha(bigint) cascade;
CREATE OR REPLACE FUNCTION operation_hash_id_alpha(opaid bigint)
returns bigint as $$ select hash_id from C.operation_alpha where autoid = opaid $$ language sql stable;

CREATE OR REPLACE FUNCTION operation_id_alpha(opaid bigint)
returns smallint as $$ select id from C.operation_alpha where autoid = opaid $$ language sql stable;

-----------------------------------------------------------------------------
-- Convenience table to rapidly get a list of operations linked to an address

CREATE TABLE IF NOT EXISTS C.operation_sender_and_receiver (
  operation_id bigint not null,
  sender_id bigint not null,
  receiver_id bigint
);
--PKEY operation_sender_and_receiver_pkey; C.operation_sender_and_receiver; operation_id --SEQONLY
--FKEY operation_sender_and_receiver_operation_id_fkey; C.operation_sender_and_receiver; operation_id; C.operation_alpha(autoid) ; CASCADE --SEQONLY
--FKEY operation_sender_and_receiver_sender_id_fkey; C.operation_sender_and_receiver; sender_id; C.addresses(address_id) ; CASCADE
--FKEY operation_sender_and_receiver_receiver_id_fkey; C.operation_sender_and_receiver; receiver_id; C.addresses(address_id) ; CASCADE
CREATE INDEX IF NOT EXISTS operation_sender_and_receiver_sender on C.operation_sender_and_receiver using btree (sender_id); --SEQONLY
CREATE INDEX IF NOT EXISTS operation_sender_and_receiver_receiver on C.operation_sender_and_receiver using btree (receiver_id); --SEQONLY

-----------------------------------------------------------------------------
-- Protocol amendment proposals

CREATE TABLE IF NOT EXISTS C.proposals (
  proposal char(51) not null,
  proposal_id bigint not null unique
  -- about proposal_id: the important factor is to have a unique
  -- value. That value could be smaller and probably using a smallint
  -- would be enough to represent all proposals happening on tezos for
  -- many years to come. However here we use a bigint, to "simply" use
  -- the first operation's ophid that needs to access `proposal_id`.
  -- The first operation that needs that access will write the
  -- proposal's hash value into the `proposal` column, and give its
  -- `ophid` as `proposal_id`. Further operations will attempt to do
  -- the same, and will fail the writing (since `proposal` is a pkey)
  -- but will be able to access `proposal_id`.
  -- All that is to avoid using Postgresql's SERIAL because those
  -- generate values that cannot be accessed within an SQL transaction.
);
--PKEY proposals_pkey; C.proposals; proposal
CREATE UNIQUE INDEX IF NOT EXISTS proposals_proposal_id on C.proposals using btree (proposal_id);

insert into c.proposals (proposal, proposal_id) values
('PsDELPH1Kxsxt8f9eWbxQeRxkjfbxoqM52jvs5Y5fBxWWh4ifpo', 1),
('PtEdoTezd3RHSC31mpxxo1npxFjoWWcFgQtxapi51Z8TLu6v6Uq', 2),
('PsCARTHAGazKbHtnKfLzQg3kms52kSRpgnDY982a9oYsSXRLQEb', 3),
('PtCarthavAMoXqbjBPVgDCRd5LgT7qqKWUPXnYii3xCaHRBMfHH', 4),
('PsBABY5HQTSkA4297zNHfsZNKtxULfL18y95qb3m53QJiXGmrbU', 5),
('PtdRxBHvc91c2ea2evV6wkoqnzW7TadTg9aqS9jAn2GbcPGtumD', 6),
('Pt24m4xiPbLDhVgVfABUjirbmda3yohdN82Sp9FeuAXJ4eV9otd', 7),
('PsBABY5nk4JhdEv1N1pZbt6m6ccB9BfNqa23iKZcHBh23jmRS9f', 8),
('Psd1ynUBhMZAeajwcZJAeq5NrxorM6UCU4GJqxZ7Bx2e9vUWB6z', 9)
on conflict do nothing;


CREATE OR REPLACE FUNCTION proposal(id bigint) returns char as $$ select proposal from C.proposals where proposal_id = id $$ language sql stable;

CREATE OR REPLACE FUNCTION proposal_id(p char) returns bigint as $$ select proposal_id from C.proposals where proposal = p $$ language sql stable;

CREATE TABLE IF NOT EXISTS C.proposal (
    operation_id bigint not null
  , source_id bigint not null
  , period int not null
  , proposal_id bigint not null
);
--PKEY proposal_pkey; C.proposal; operation_id, proposal_id
--FKEY proposal_operation_id_fkey; C.proposal; operation_id; C.operation_alpha(autoid); CASCADE --SEQONLY
--FKEY proposal_source_fkey; C.proposal; source_id; C.addresses(address_id); CASCADE --SEQONLY
--FKEY proposal_proposal_id_fkey; C.proposal; proposal_id; C.proposals(proposal_id); CASCADE --SEQONLY
CREATE INDEX IF NOT EXISTS proposal_operation on C.proposal using btree (operation_id);
CREATE INDEX IF NOT EXISTS proposal_source on C.proposal using btree (source_id); --SEQONLY
CREATE INDEX IF NOT EXISTS proposal_proposal on C.proposal using btree (proposal_id);
CREATE INDEX IF NOT EXISTS proposal_period on C.proposal using btree (period); --SEQONLY

-----------------------------------------------------------------------------
-- Ballots for proposal amendment proposals
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'one_ballot') THEN
    CREATE TYPE one_ballot AS ENUM ('nay', 'yay', 'pass');
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS C.ballot (
    operation_id bigint not null
  , source_id bigint not null
  , period int not null
  , proposal_id bigint not null
  , ballot one_ballot not null
);
--PKEY ballot_pkey; C.ballot; operation_id --SEQONLY
--FKEY ballot_operation_id_fkey; C.ballot; operation_id; C.operation_alpha(autoid); CASCADE --SEQONLY
--FKEY ballot_proposal_id_fkey; C.ballot; proposal_id; C.proposals(proposal_id); CASCADE --SEQONLY
CREATE INDEX IF NOT EXISTS ballot_source on C.ballot using btree (source_id); --SEQONLY


-----------------------------------------------------------------------------
-- Double endorsement evidence

CREATE TABLE IF NOT EXISTS C.double_endorsement_evidence (
    operation_id bigint not null
  , op1 jsonb not null
  , op2 jsonb not null
);
--PKEY double_endorsement_evidence_pkey; C.double_endorsement_evidence; operation_id --SEQONLY
--FKEY double_endorsement_evidence_operation_id_fkey; C.double_endorsement_evidence; operation_id; C.operation_alpha(autoid); CASCADE --SEQONLY


-----------------------------------------------------------------------------
-- Double baking evidence

CREATE TABLE IF NOT EXISTS C.double_baking_evidence (
    operation_id bigint not null
  , bh1 jsonb not null -- block header 1
  , bh2 jsonb not null -- block header 2
);
--PKEY double_baking_evidence_pkey; C.double_baking_evidence; operation_id --SEQONLY
--FKEY double_baking_evidence_operation_id_fkey; C.double_baking_evidence;operation_id; C.operation_alpha(autoid); CASCADE --SEQONLY


-----------------------------------------------------------------------------
-- Common data for manager operations

CREATE TABLE IF NOT EXISTS C.manager_numbers (
    operation_id bigint not null
  , counter numeric
  -- counter
  , gas_limit numeric
  -- gas limit
  , storage_limit numeric
  -- storage limit
);
--PKEY manager_numbers_pkey; C.manager_numbers; operation_id --SEQONLY
--FKEY manager_numbers_operation_id_fkey; C.manager_numbers; operation_id; C.operation_alpha(autoid); CASCADE --SEQONLY
-- Not sure the following indexes are relevant:
--OPT CREATE INDEX IF NOT EXISTS manager_numbers_counter on C.manager_numbers using btree (counter); --SEQONLY
--OPT CREATE INDEX IF NOT EXISTS manager_numbers_gas_limit on C.manager_numbers using btree (gas_limit); --SEQONLY
--OPT CREATE INDEX IF NOT EXISTS manager_numbers_storage_limit on C.manager_numbers using btree (storage_limit); --SEQONLY


-----------------------------------------------------------------------------
-- Account Activations

CREATE TABLE IF NOT EXISTS C.activation (
   operation_id bigint not null
 , pkh_id bigint not null
 , activation_code text not null
);
--PKEY activation_pkey; C.activation; operation_id --SEQONLY
--FKEY activation_operation_id_fkey; C.activation; operation_id; C.operation_alpha(autoid) ; CASCADE --SEQONLY
--FKEY activation_pkh_fkey; C.activation; pkh_id; C.addresses(address_id) ; CASCADE --SEQONLY


-----------------------------------------------------------------------------
-- Endorsements

CREATE TABLE IF NOT EXISTS C.endorsement (
   operation_id bigint not null
 , level int
 , delegate_id bigint
 , slots smallint[]
);
--PKEY endorsement_pkey; C.endorsement; operation_id --SEQONLY
--FKEY endorsement_operation_id_fkey; C.endorsement; operation_id; C.operation_alpha(autoid) ; CASCADE --SEQONLY
--FKEY endorsement_delegate_fkey; C.endorsement; delegate_id; C.addresses(address_id) ; CASCADE --SEQONLY
CREATE INDEX IF NOT EXISTS endorsement_delegate_id on C.endorsement using btree (delegate_id); --SEQONLY


-----------------------------------------------------------------------------
-- Seed nonce revelation

CREATE TABLE IF NOT EXISTS C.seed_nonce_revelation (
    operation_id bigint not null
  -- index of the operation in the block's list of operations
 , level int not null
 , nonce char(66) not null
);
--PKEY seed_nonce_revelation_pkey; C.seed_nonce_revelation; operation_id --SEQONLY
--FKEY seed_nonce_revelation_operation_id_fkey; C.seed_nonce_revelation; operation_id; C.operation_alpha(autoid); CASCADE --SEQONLY


-----------------------------------------------------------------------------
-- Blocks at alpha level.
-- "level_position = cycle * blocks_per_cycle + cycle_position"

CREATE TABLE IF NOT EXISTS C.block_alpha (
  hash_id int not null
  -- block hash id
  , baker_id bigint not null
  -- pkh of baker
  , level_position int not null
  /* Verbatim from lib_protocol/level_repr:
     The level of the block relative to the block that
     starts protocol alpha. This is specific to the
     protocol alpha. Other protocols might or might not
     include a similar notion.
  */
  , cycle int not null
  -- cycle
  , cycle_position int not null
  /* Verbatim from lib_protocol/level_repr:
     The current level of the block relative to the first
     block of the current cycle.
  */
  , voting_period jsonb not null
  /* increasing integer.
     from proto_alpha/level_repr:
     voting_period = level_position / blocks_per_voting_period */
  , voting_period_position int not null
  -- voting_period_position = remainder(level_position / blocks_per_voting_period)
  , voting_period_kind smallint not null
  /* Proposal = 0
     Testing_vote = 1
     Testing = 2
     Promotion_vote = 3
     Adoption = 4
   */
  , consumed_milligas numeric not null
  /* total milligas consumed by block. Arbitrary-precision integer. */
);
--PKEY block_alpha_pkey; C.block_alpha; hash_id --SEQONLY
--FKEY block_alpha_hash_fkey; C.block_alpha; hash_id; C.block(hash_id); CASCADE --SEQONLY
--FKEY block_alpha_baker_fkey; C.block_alpha; baker_id; C.addresses(address_id); CASCADE --SEQONLY
CREATE INDEX IF NOT EXISTS block_alpha_baker on C.block_alpha using btree (baker_id); --SEQONLY
CREATE INDEX IF NOT EXISTS block_alpha_level_position on C.block_alpha using btree (level_position); --SEQONLY
CREATE INDEX IF NOT EXISTS block_alpha_cycle on C.block_alpha using btree (cycle); --SEQONLY
CREATE INDEX IF NOT EXISTS block_alpha_cycle_position on C.block_alpha using btree (cycle_position); --SEQONLY
-- CREATE INDEX IF NOT EXISTS block_alpha_hash on C.block_alpha using btree (hash_id); --useless if hash_id is pkey

-----------------------------------------------------------------------------
-- Deactivated accounts

CREATE TABLE IF NOT EXISTS C.deactivated (
  pkh_id bigint not null,
  -- pkh of the deactivated account(tz1...)
  block_hash_id int not null
  -- block hash at which deactivation occured
);
--PKEY deactivated_pkey; C.deactivated; pkh_id, block_hash_id  --SEQONLY
--FKEY deactivated_pkh_fkey; C.deactivated; pkh_id; C.addresses(address_id); CASCADE --SEQONLY
--FKEY deactivated_block_hash_fkey; C.deactivated; block_hash_id; C.block(hash_id); CASCADE --SEQONLY
CREATE INDEX IF NOT EXISTS deactivated_pkh on C.deactivated using btree (pkh_id); --SEQONLY
CREATE INDEX IF NOT EXISTS deactivated_block_hash on C.deactivated using btree (block_hash_id); --SEQONLY
--CREATE INDEX IF NOT EXISTS deactivated_autoid on C.deactivated using btree (autoid); --OPT --SEQONLY --FIXME: is it useful?

-----------------------------------------------------------------------------
-- Contract (implicit:tz1... or originated:KT1...) table
-- two ways of updating this table:
-- - on bootstrap, scanning preexisting contracts
-- - when scanning ops, looking at an origination/revelation

CREATE TABLE IF NOT EXISTS C.contract (
  address_id bigint not null,
  -- contract address, b58check format
  block_hash_id int not null,
  -- block hash
  mgr_id bigint,
  -- manager
  delegate_id bigint,
  -- delegate
  spendable bool,
  -- spendable flag -- obsolete since proto 5
  delegatable bool,
  -- delegatable flag, soon obsolete?
  credit bigint,
  -- credit
  preorig_id bigint,
  -- comment from proto_alpha/apply:
  -- The preorigination field is only used to early return
  -- the address of an originated contract in Michelson.
  -- It cannot come from the outside.
  script jsonb,
  -- Json-encoded Micheline script
  block_level int not null
);
--PKEY contract_pkey; C.contract; address_id, block_hash_id
--FKEY contract_block_hash_fkey; C.contract; block_hash_id; C.block(hash_id); CASCADE --SEQONLY
--FKEY contract_mgr_fkey; C.contract; mgr_id; C.addresses(address_id); CASCADE --SEQONLY
--FKEY contract_preorig_fkey; C.contract; preorig_id; C.addresses(address_id); CASCADE --SEQONLY
--FKEY contract_address_fkey; C.contract; address_id; C.addresses(address_id); CASCADE --SEQONLY
--FKEY contract_delegate_fkey; C.contract; delegate_id; C.addresses(address_id); CASCADE --SEQONLY
CREATE INDEX IF NOT EXISTS contract_block on C.contract using btree (block_hash_id); --SEQONLY
CREATE INDEX IF NOT EXISTS contract_block_level on C.contract using btree (block_level);
CREATE INDEX IF NOT EXISTS contract_mgr on C.contract using btree (mgr_id); --SEQONLY
CREATE INDEX IF NOT EXISTS contract_delegate on C.contract using btree (delegate_id); --SEQONLY
CREATE INDEX IF NOT EXISTS contract_preorig on C.contract using btree (preorig_id); --SEQONLY
CREATE INDEX IF NOT EXISTS contract_address on C.contract using btree (address_id); --SEQONLY


-----------------------------------------------------------------------------
-- Table of contract balance by block level: each time a contract has its balance updated, we write it here

CREATE TABLE IF NOT EXISTS C.contract_balance (
  address_id bigint not null,
  block_hash_id int not null,
  balance bigint, -- make it nullable so that it can be filled asynchronously
  block_level int not null -- this field is only meant to speed up searches
  -- N.B. it would be bad to have "address_id" as a primary key,
  -- because if you update a contract's balance using a
  -- rejected block(uncle block) and then the new balance is not updated
  -- once the rejected block is discovered,
  -- you end up with wrong information
);
--PKEY contract_balance_pkey; C.contract_balance; address_id, block_hash_id  --SEQONLY
--FKEY contract_balance_address_fkey; C.contract_balance; address_id; C.addresses(address_id); CASCADE --SEQONLY
--FKEY contract_balance_block_hash_block_level_fkey; C.contract_balance; block_hash_id, block_level; C.block(hash_id, level); CASCADE --SEQONLY
CREATE INDEX IF NOT EXISTS contract_balance_block_level on C.contract_balance using btree (block_level); --SEQONLY
CREATE INDEX IF NOT EXISTS contract_balance_address on C.contract_balance using btree (address_id); --SEQONLY
CREATE INDEX IF NOT EXISTS contract_balance_address_block_level on C.contract_balance using btree (address_id, block_level desc); --SEQONLY
CREATE INDEX IF NOT EXISTS contract_balance_block_hash on C.contract_balance using btree (block_hash_id); --SEQONLY


-----------------------------------------------------------------------------
-- Transactions

CREATE TABLE IF NOT EXISTS C.tx (
  operation_id bigint not null,
  -- operation id from operation_alpha
  source_id bigint not null,
  -- source address
  destination_id bigint not null,
  -- dest address
  fee bigint not null,
  -- fees
  amount bigint not null,
  -- amount
  parameters text,
  -- optional parameters to contract in json-encoded Micheline
  storage jsonb,
  -- optional parameter for storage update
  consumed_milligas numeric not null,
  -- consumed milligas
  storage_size numeric not null,
  -- storage size
  paid_storage_size_diff numeric not null,
  -- paid storage size diff
  entrypoint text,
  -- entrypoint
  nonce int -- non null for internal operations
);
--PKEY tx_pkey; C.tx; operation_id --SEQONLY
--FKEY tx_operation_id_fkey; C.tx; operation_id; C.operation_alpha(autoid); CASCADE --SEQONLY
--FKEY tx_source_fkey; C.tx; source_id; C.addresses(address_id); CASCADE --SEQONLY
--FKEY tx_destination_fkey; C.tx; destination_id; C.addresses(address_id); CASCADE --SEQONLY
CREATE INDEX IF NOT EXISTS tx_source on C.tx using btree (source_id); --SEQONLY
CREATE INDEX IF NOT EXISTS tx_destination on C.tx using btree (destination_id); --SEQONLY


-----------------------------------------------------------------------------
-- Origination table

CREATE TABLE IF NOT EXISTS C.origination (
  operation_id bigint not null,
  -- operation id from operation_alpha
  source_id bigint not null,
  -- source of origination op
  k_id bigint not null,
  -- address of originated contract
  consumed_milligas numeric not null,
  -- consumed milligas
  storage_size numeric not null,
  -- storage size
  paid_storage_size_diff numeric not null,
  -- paid storage size diff
  fee bigint not null,
  -- fees
  nonce int -- non null for internal operations
);
--PKEY origination_pkey; C.origination; operation_id --SEQONLY
--FKEY origination_operation_id_fkey; C.origination; operation_id; C.operation_alpha(autoid); CASCADE --SEQONLY
--FKEY origination_operation_source_fkey; C.origination; source_id; C.addresses(address_id); CASCADE --SEQONLY
--FKEY origination_k_fkey; C.origination; k_id; C.addresses(address_id); CASCADE --SEQONLY
CREATE INDEX IF NOT EXISTS origination_source         on C.origination using btree (source_id); --SEQONLY
CREATE INDEX IF NOT EXISTS origination_k              on C.origination using btree (k_id); --SEQONLY


-----------------------------------------------------------------------------
-- Delegation

CREATE TABLE IF NOT EXISTS C.delegation (
  operation_id bigint not null
  -- operation id from operation_alpha
  , source_id bigint not null
  -- source of the delegation op
  , pkh_id bigint
  -- optional delegate
  , consumed_milligas numeric -- nullable because of proto 1 & 2
  -- consumed milligas
  , fee bigint not null
  -- fees
  , nonce int -- non null for internal operations
);
--PKEY delegation_pkey; C.delegation; operation_id --SEQONLY
--FKEY delegation_operation_id_fkey; C.delegation; operation_id; C.operation_alpha(autoid); CASCADE --SEQONLY
--FKEY delegation_source_fkey; C.delegation; source_id; C.addresses(address_id); CASCADE --SEQONLY
--FKEY delegation_pkh_fkey; C.delegation; pkh_id; C.addresses(address_id); CASCADE --SEQONLY
CREATE INDEX IF NOT EXISTS delegation_source         on C.delegation using btree (source_id); --SEQONLY
CREATE INDEX IF NOT EXISTS delegation_pkh            on C.delegation using btree (pkh_id); --SEQONLY
CREATE INDEX IF NOT EXISTS delegation_operation_hash on C.delegation using btree (operation_id); --SEQONLY


-----------------------------------------------------------------------------
-- Reveals

CREATE TABLE IF NOT EXISTS C.reveal (
    operation_id bigint not null
  -- operation id from operation_alpha
  , source_id bigint not null
  -- source
  , pk char(55) not null
  -- revealed pk
  , consumed_milligas numeric -- nullable because of proto 1 & 2
  -- consumed milligas
  , fee bigint not null
  -- fees
  , nonce int -- non null for internal operations
);
--PKEY reveal_pkey; C.reveal; operation_id --SEQONLY
--FKEY reveal_operation_hash_op_id_fkey; C.reveal; operation_id; C.operation_alpha(autoid); CASCADE --SEQONLY
--FKEY reveal_source_fkey; C.reveal; source_id; C.addresses(address_id); CASCADE --SEQONLY
CREATE INDEX IF NOT EXISTS reveal_source         on C.reveal using btree (source_id); --SEQONLY
CREATE INDEX IF NOT EXISTS reveal_pkh            on C.reveal using btree (pk); --SEQONLY


-----------------------------------------------------------------------------
-- Balance: record balance diffs

CREATE TABLE IF NOT EXISTS C.balance_updates_block (
  block_hash_id int not null,
  -- block hash
  balance_kind smallint not null,
  -- balance kind:
  -- 0 : Contract
  -- 1 : Rewards
  -- 2 : Fees
  -- 3 : Deposits
  -- see proto_alpha/delegate_storage.ml/balance
  contract_address_id bigint not null,
  -- b58check encoded address of contract(either implicit or originated)
  cycle int, -- only balance_kind 1,2,3 have cycle
  -- cycle
  diff bigint not null,
  -- balance update
  -- credited if positve
  -- debited if negative
  id int not null -- unique position within the block to allow rightful duplicates and reject wrong duplicates
  , primary key (block_hash_id, id)
);
--PKEY balance_updates_block_pkey; C.balance_updates_block; block_hash_id, id --SEQONLY
--FKEY balance_block_block_hash_fkey; C.balance_updates_block; block_hash_id; C.block(hash_id); CASCADE --SEQONLY
--FKEY balance_block__contract_address_fkey; C.balance_updates_block; contract_address_id; C.addresses(address_id); CASCADE --SEQONLY
CREATE INDEX IF NOT EXISTS balance_block  on C.balance_updates_block using btree (block_hash_id); --SEQONLY
CREATE INDEX IF NOT EXISTS balance_cat    on C.balance_updates_block using btree (balance_kind); --SEQONLY
CREATE INDEX IF NOT EXISTS balance_k      on C.balance_updates_block using btree (contract_address_id); --SEQONLY
CREATE INDEX IF NOT EXISTS balance_cycle  on C.balance_updates_block using btree (cycle); --SEQONLY


CREATE TABLE IF NOT EXISTS C.balance_updates_op (
  operation_id bigint not null,
  balance_kind smallint not null,
  -- balance kind:
  -- 0 : Contract
  -- 1 : Rewards
  -- 2 : Fees
  -- 3 : Deposits
  -- see proto_alpha/delegate_storage.ml/balance
  contract_address_id bigint not null,
  -- b58check encoded address of contract(either implicit or originated)
  cycle int, -- only balance_kind 1,2,3 have cycle
  -- cycle
  diff bigint not null,
  -- balance update
  -- credited if positve
  -- debited if negative
  id int not null -- unique position within the block (or operation?) to allow rightful duplicates and reject wrong duplicates - some are positive, some negative
  , primary key (operation_id, id)
);
--PKEY balance_updates_op_pkey; C.balance_updates_op; operation_id, id --SEQONLY
--FKEY balance_block_op_operation_id_fkey; C.balance_updates_op; operation_id; C.operation_alpha(autoid); CASCADE --SEQONLY
--FKEY balance_contract_address_fkey; C.balance_updates_op; contract_address_id; C.addresses(address_id); CASCADE --SEQONLY
CREATE INDEX IF NOT EXISTS balance_operation_id on C.balance_updates_op using btree (operation_id); --SEQONLY
CREATE INDEX IF NOT EXISTS balance_cat          on C.balance_updates_op using btree (balance_kind); --SEQONLY
CREATE INDEX IF NOT EXISTS balance_k            on C.balance_updates_op using btree (contract_address_id); --SEQONLY
CREATE INDEX IF NOT EXISTS balance_cycle        on C.balance_updates_op using btree (cycle); --SEQONLY


-----------------------------------------------------------------------------
-- Snapshot blocks
-- The snapshot block for a given cycle is obtained as follows
-- at the last block of cycle n, the snapshot block for cycle n+6 is selected
-- Use [Storage.Roll.Snapshot_for_cycle.get C.txt cycle] in proto_alpha to
-- obtain this value.
-- RPC: /chains/main/blocks/${block}/context/raw/json/cycle/${cycle}
-- where:
-- ${block} denotes a block(either by hash or level)
-- ${cycle} denotes a cycle which must be in [cycle_of(level)-5,cycle_of(level)+7]

CREATE TABLE IF NOT EXISTS C.snapshot (
  cycle int,
  level int,
  primary key (cycle, level)
);

-----------------------------------------------------------------------------
-- Could be useful for baking.
-- CREATE TABLE IF NOT EXISTS delegate (
--   cycle int not null,
--   level int not null,
--   pkh char(36) not null,
--   balance bigint not null,
--   frozen_balance bigint not null,
--   staking_balance bigint not null,
--   delegated_balance bigint not null,
--   deactivated bool not null,
--   grace smallint not null,
--   primary key (cycle, pkh),
--   , foreign key (cycle, level) references snapshot(cycle, level)
--   , foreign key (pkh) references implicit(pkh)
-- );

-----------------------------------------------------------------------------
-- Delegated contract table -- NOT FILLED

CREATE TABLE IF NOT EXISTS C.delegated_contract (
  delegate_id bigint,
  -- tz1 of the delegate
  delegator_id bigint,
  -- address of the delegator (for now, KT1 but this could change)
  cycle int,
  level int
  , primary key (delegate_id, delegator_id, cycle, level)
);
--PKEY delegated_contract_pkey; C.delegated_contract; delegate_id, delegator_id, cycle, level --SEQONLY
--FKEY delegated_contract_delegate_fkey; C.delegated_contract; delegate_id; C.addresses(address_id); CASCADE --SEQONLY
--FKEY delegated_contract_delegator_fkey; C.delegated_contract; delegator_id; C.addresses(address_id); CASCADE --SEQONLY
--FKEY delegated_contract_cycle_level_fkey; C.delegated_contract; cycle, level; C.snapshot(cycle, level); CASCADE --SEQONLY
CREATE INDEX IF NOT EXISTS delegated_contract_cycle     on C.delegated_contract using btree (cycle); --SEQONLY
CREATE INDEX IF NOT EXISTS delegated_contract_level     on C.delegated_contract using btree (level); --SEQONLY
CREATE INDEX IF NOT EXISTS delegated_contract_delegate  on C.delegated_contract using btree (delegate_id); --SEQONLY
CREATE INDEX IF NOT EXISTS delegated_contract_delegator on C.delegated_contract using btree (delegator_id); --SEQONLY

-----------------------------------------------------------------------------
-- Could be useful for baking.
-- CREATE TABLE IF NOT EXISTS stake (
--   delegate char(36) not null,
--   level int not null,
--   k char(36) not null,
--   kind smallint not null,
--   diff bigint not null,
--   primary key (delegate, level, k, kind, diff),
--   , foreign key (delegate) references implicit(pkh)
--   , foreign key (k) references C.addresses(address_id)
-- );
-- src/db-schema/chain_functions.sql
-- Open Source License
-- Copyright (c) 2019-2021 Nomadic Labs <contact@nomadic-labs.com>
--
-- Permission is hereby granted, free of charge, to any person obtaining a
-- copy of this software and associated documentation files (the "Software"),
-- to deal in the Software without restriction, including without limitation
-- the rights to use, copy, modify, merge, publish, distribute, sublicense,
-- and/or sell copies of the Software, and to permit persons to whom the
-- Software is furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included
-- in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
-- THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
-- FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
-- DEALINGS IN THE SOFTWARE.

-----------------------------------------------------------------------------
-- Naming conventions:
-- - for functions:
--   * I.table -> insert into table
--   * U_table -> update table
--   * IU_table -> insert or update table (aka upsert)
--   * u_concept -> update more than one table
--   * B_action -> action on bigmaps
--   * BEWARE: upper/lower cases for prefixes are only for aesthetic purposes!
--     Function names are case-insensitive!
-----------------------------------------------------------------------------

SELECT 'chain_functions.sql' as file;


CREATE OR REPLACE FUNCTION I.chain(c char)
RETURNS void
AS $$
BEGIN
insert into C.chain(hash) values (c)
on conflict do nothing;
if (select count(*) from C.chain) <> 1
then
  raise 'You are trying to index a chain on a other chain‘s database.';
end if;
end;
$$ LANGUAGE PLPGSQL;

CREATE OR REPLACE FUNCTION I.block_hash_aux(bh char, bhid int)
RETURNS int
AS $$
insert into C.block_hash values (bh, bhid) on conflict do nothing returning hash_id;
$$ language SQL;

CREATE OR REPLACE FUNCTION I.block(bh char, l int, p int, pr char, t timestamp, vp smallint, m char, f char, c char)
RETURNS int
AS $$
DECLARE bhid int := null;
BEGIN
bhid := (select I.block_hash_aux(bh, l));
if bhid is null --SEQONLY
then --SEQONLY
  bhid := (select I.block_hash_aux(bh, -l)); --SEQONLY
  if bhid is null --SEQONLY
  then --SEQONLY
    bhid := (select I.block_hash_aux(bh, -l+(random()*10000)::int)); --SEQONLY
    if bhid is null --SEQONLY
    then --SEQONLY
      raise 'Failed to record block %', bh; --SEQONLY
    end if; --SEQONLY
  end if; --SEQONLY
end if; --SEQONLY
insert into C.block values (bhid, l, p, l-1, t, vp, m, f, c)
on conflict do nothing  --conflict
;
return bhid;
END;
$$ LANGUAGE PLPGSQL;



CREATE OR REPLACE FUNCTION I.block0(bh char, l int, p int, pr char, t timestamp, vp smallint, m char, f char, c char)
RETURNS int
AS $$
-- pr is unused but it might be better if we make sure that (pr=bh)
insert into C.block_hash values (bh, l) on conflict do nothing;
-- the following insert will fail if bh≠pr, unless for some reason pr was inserted before
insert into C.block values (block_hash_id(bh), l, p, block_hash_id(pr), t, vp, m, f, c)
on conflict do nothing --conflict
;
select block_hash_id(bh);
$$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION confirm_block(bhid int, depth smallint)
RETURNS void
AS $$
update C.block set indexing_depth = depth where hash_id = bhid; --SEQONLY
$$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION record_log (msg text)
RETURNS void
AS $$
insert into indexer_log values (CURRENT_TIMESTAMP, '', '', msg) on conflict do nothing;
$$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION max_level()
RETURNS int
AS $$
select level from C.block
order by level desc limit 1;
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION I.operation_aux(h char, b int, hi bigint)
RETURNS bigint
AS $$
insert into C.operation (hash, block_hash_id, hash_id)
values (h, b, hi)
on conflict do nothing
returning hash_id;
$$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION I.operation(h char, b int, hi bigint)
RETURNS bigint
AS $$
DECLARE r bigint := null;
BEGIN
r := I.operation_aux(h, b, hi);
if r is not null
then
  return r;
else
  r := (select hash_id from C.operation where hash = h);
  return r;
end if;
END
$$ LANGUAGE PLPGSQL;



CREATE OR REPLACE FUNCTION I.block_alpha (bhid int, baker bigint, level_position int, cycle int, cycle_position int, voting_period jsonb, voting_period_position int, voting_period_kind smallint, consumed_milligas numeric)
returns void
as $$
insert into C.block_alpha
values (bhid, baker, level_position, cycle, cycle_position, voting_period, voting_period_position, voting_period_kind, consumed_milligas)
on conflict do nothing --CONFLICT
;
$$ language sql;


CREATE OR REPLACE FUNCTION I.opalpha (ophid bigint, opid smallint, opkind smallint, bhid int, i smallint, a bigint)
returns void
as $$
insert into C.operation_alpha(hash_id, id, operation_kind, block_hash_id, internal, autoid)
values (ophid, opid, opkind, bhid, i, a)
on conflict do nothing --CONFLICT
$$ language sql;


CREATE OR REPLACE FUNCTION I.deactivated (pkhid bigint, bhid int)
returns void
as $$
insert into C.deactivated (pkh_id, block_hash_id) values (pkhid, bhid)
on conflict do nothing  --CONFLICT
$$ language sql;


CREATE OR REPLACE FUNCTION I.activate (opaid bigint, pkhid bigint, ac char)
returns void
as $$
insert into C.activation(operation_id, pkh_id, activation_code)
values (opaid, pkhid, ac)
on conflict do nothing; --CONFLICT
$$ language sql;


DROP FUNCTION IF EXISTS I.proposal (bigint, bigint, bigint, int, char);
CREATE OR REPLACE FUNCTION I.proposal (opaid bigint, i bigint, s bigint, period int, proposal char)
RETURNS VOID
AS $$
insert into C.proposals values (proposal, i) on conflict do nothing;
insert into C.proposal values (opaid, s, period, proposal_id(proposal))
on conflict do nothing --CONFLICT
;
insert into C.operation_sender_and_receiver values (opaid, s, null)
on conflict do nothing; --CONFLICT
$$ LANGUAGE SQL;

CREATE OR REPLACE FUNCTION I.proposal2 (opaid bigint, i bigint, s bigint, period int, proposal char)
RETURNS VOID
AS $$
-- the only difference with I.proposal is that this one does not create an entry in C.operation_sender_and_receiver because we know there already is one
insert into C.proposals values (proposal, i) on conflict do nothing;
insert into C.proposal values (opaid, s, period, proposal_id(proposal))
on conflict do nothing --CONFLICT
;
$$ LANGUAGE SQL;


DROP FUNCTION IF EXISTS I.ballot (bigint, bigint, bigint, int, char, one_ballot);
CREATE OR REPLACE FUNCTION I.ballot (opaid bigint, i bigint, s bigint, period int, proposal char, ballot one_ballot)
RETURNS VOID
AS $$
-- in non-multicore mode, there's no vote for proposals that are unknown
-- in multicore mode, we can be recording ballots for proposals that haven't been recorded yet
insert into C.ballot
values (opaid, s, period, proposal_id(proposal), ballot)
on conflict do nothing --CONFLICT
;
insert into C.operation_sender_and_receiver values (opaid, s, null)
on conflict do nothing; --CONFLICT
$$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION I.double_endorsement(opaid bigint, baker_id bigint, offender_id bigint, op1 jsonb, op2 jsonb)
RETURNS void
AS $$
insert into C.double_endorsement_evidence values (opaid, op1, op2)
on conflict do nothing --CONFLICT
;
insert into C.operation_sender_and_receiver values (opaid, baker_id, offender_id)
on conflict do nothing;
$$ LANGUAGE SQL;



CREATE OR REPLACE FUNCTION I.double_baking(opaid bigint, bh1 jsonb, bh2 jsonb, baker_id bigint, offender_id bigint)
RETURNS void
AS $$
insert into C.double_baking_evidence values (opaid, bh1, bh2)
on conflict do nothing --CONFLICT
;
insert into C.operation_sender_and_receiver values (opaid, baker_id, offender_id)
on conflict do nothing;
$$ LANGUAGE SQL;



CREATE OR REPLACE FUNCTION I.manager_numbers (opaid bigint, counter numeric, gas_limit numeric, storage_limit numeric)
returns void
as $$
insert into C.manager_numbers
values (opaid, counter, gas_limit, storage_limit)
on conflict do nothing --CONFLICT
;
$$ language sql;


CREATE OR REPLACE FUNCTION I.endorsement(opaid bigint, level int, del bigint, sl smallint[])
returns void
as $$
insert into C.endorsement values (opaid, level, del, sl)
on conflict (operation_id) do nothing --CONFLICT
;
insert into C.operation_sender_and_receiver values (opaid, del, null)
on conflict do nothing --CONFLICT
;
$$ language sql;


CREATE OR REPLACE FUNCTION I.seed_nonce (opaid bigint, sender_id bigint, baker_id bigint, l int, n char)
returns void
as $$
insert into C.seed_nonce_revelation (operation_id, level, nonce)
values (opaid, l, n)
on conflict do nothing --CONFLICT
;
insert into C.operation_sender_and_receiver values (
  opaid
, sender_id
, baker_id
)
on conflict do nothing --CONFLICT
;
$$ language sql;


CREATE OR REPLACE FUNCTION I.snapshot (c int, l int)
returns void
as $$
insert into C.snapshot
values (c, l)
on conflict do nothing;
$$ language sql;


-- this is only for updating the script on mainnet after transitioning to Babylon
CREATE OR REPLACE FUNCTION U.contract_s (k bigint, xscript jsonb, bl int)
returns void
as $$
with c as --conflict
(select block_hash_id, address_id from C.contract where address_id = k and script is null and block_level <= bl order by block_level desc limit 1) --conflict
update C.contract c2 set script = xscript, block_level = bl from c where (c2.block_hash_id, c2.address_id) = (C.block_hash_id, C.address_id) ; --conflict
$$ language sql;


CREATE OR REPLACE FUNCTION G.scriptless_contracts ()
-- relevant only for mainnet
returns table (address char, address_id bigint)
as $$
with i as (
select address_id --CONFLICT
from C.addresses --CONFLICT
where address like 'K%' --CONFLICT
intersect --CONFLICT
select address_id --CONFLICT
from C.contract c1 --CONFLICT
where c1.script is null --CONFLICT
and c1.block_level < 655360 --CONFLICT
and not exists (select * from C.contract c2 where c2.address_id = c1.address_id and c2.script is not null) --CONFLICT
--NONCONFLICT select address_id from C.contract where false
) select address, a.address_id from C.addresses a, i where a.address_id = i.address_id;
$$ language sql stable;



CREATE OR REPLACE FUNCTION U.contract_de (xdelegate bigint, xaddress bigint, bhid int, bl int)
returns void
as $$
insert into C.contract (delegate_id, address_id, block_hash_id, block_level) --conflict
values (xdelegate, xaddress, bhid, bl) --conflict
on conflict (address_id, block_hash_id) --conflict
do update set delegate_id = xdelegate, block_level = bl --conflict
where C.contract.address_id = xaddress and C.contract.block_hash_id = bhid and C.contract.block_level <= bl; --conflict
$$ language sql;



CREATE OR REPLACE FUNCTION U.contract_di (xaddress bigint, bhid int, xmgr bigint, xspendable bool, xdelegatable bool, xscript jsonb, bl int)
returns void
as $$
insert into C.contract (address_id, block_hash_id, mgr_id, spendable, delegatable, script, block_level) --conflict
values (xaddress, bhid, xmgr, xspendable, xdelegatable, xscript, bl) --conflict
on conflict (address_id, block_hash_id) --conflict
do update set mgr_id = xmgr, spendable = xspendable, delegatable = xdelegatable, script = xscript --conflict
where C.contract.address_id = xaddress and C.contract.block_hash_id = bhid and C.contract.block_level <= bl --conflict
$$ language sql;



CREATE OR REPLACE FUNCTION U.c_bal (xaddress bigint, bhid int, xbalance bigint)
returns void
as $$
update C.contract_balance set balance = xbalance where block_hash_id = bhid and address_id = xaddress;
$$ language sql;


CREATE OR REPLACE FUNCTION I.c_bal (xaddress bigint, bhid int, xbalance bigint, xblock_level int)
returns void
as $$
insert into C.contract_balance (address_id, block_hash_id, balance, block_level)
values (xaddress, bhid, xbalance, xblock_level)
on conflict do nothing --CONFLICT
;
$$ language sql;


CREATE OR REPLACE FUNCTION H.c_bal (xaddress bigint, bhid int, xblock_level int)
returns void
as $$
insert into C.contract_balance (address_id, block_hash_id, block_level)
values (xaddress, bhid, xblock_level)
on conflict do nothing --CONFLICT
;
$$ language sql;


CREATE OR REPLACE FUNCTION G.balanceless_contracts (block_level_min int, block_level_max int, lim bigint)
returns table(address char, address_id bigint, block_hash char, block_hash_id int, block_level int) -- block_level is for logs
as $$
select address(address_id) as address, address_id, block_hash(block_hash_id) as block_hash, block_hash_id, block_level
from C.contract_balance
where balance is null and block_level >= block_level_min and block_level <= block_level_max
limit lim;
$$ language sql stable;


CREATE OR REPLACE FUNCTION I.tx (opaid bigint, n int, c bigint, d bigint, e bigint, f bigint, g text, h jsonb, ii numeric, j numeric, k numeric, ep char)
RETURNS void
AS $$
insert into C.tx values (opaid, c, d, e, f, g, h, ii, j, k, ep, n)
on conflict do nothing --CONFLICT
;
insert into C.operation_sender_and_receiver values (opaid, c, d)
on conflict do nothing --CONFLICT
;
$$ LANGUAGE SQL;



CREATE OR REPLACE FUNCTION I.origination (opaid bigint, source bigint, k bigint, consumed_milligas numeric, storage_size numeric, paid_storage_size_diff numeric, fee bigint, nonce int)
returns void
as $$
insert into C.origination
values
(opaid, source, k, consumed_milligas, storage_size, paid_storage_size_diff, fee, nonce)
on conflict do nothing --CONFLICT
;
insert into C.operation_sender_and_receiver
values (opaid, source, k)
on conflict do nothing --CONFLICT
;
$$ language sql;


CREATE OR REPLACE FUNCTION I.delegation (opaid bigint, source bigint, pkh bigint, gas numeric, f bigint, n int)
returns void
as $$
insert into C.delegation values (opaid, source, pkh, gas, f, n)
on conflict do nothing --CONFLICT
;
insert into C.operation_sender_and_receiver values (opaid, source, pkh)
on conflict do nothing --CONFLICT
;
$$ language sql;


CREATE OR REPLACE FUNCTION I.reveal (opaid bigint, source bigint, pk char, gas numeric, f bigint, n int)
returns void
as $$
insert into C.reveal values (opaid, source, pk, gas, f, n)
on conflict do nothing --CONFLICT
;
insert into C.operation_sender_and_receiver values (opaid, source, null)
on conflict do nothing --CONFLICT
;
$$ language sql;


CREATE OR REPLACE FUNCTION I.balance_o (opaid bigint, bal smallint, k bigint, cy int, di bigint, id int)
returns void
as $$
insert into C.balance_updates_op (operation_id, balance_kind, contract_address_id, cycle, diff, id)
values (opaid, bal, k, cy, di, id)
on conflict do nothing --CONFLICT
;
$$ language sql;


CREATE OR REPLACE FUNCTION I.balance_b (bhid int, bal smallint, k bigint, cy int, di bigint, id int)
returns void
as $$
insert into C.balance_updates_block (block_hash_id, balance_kind, contract_address_id, cycle, diff, id)
values (bhid, bal, k, cy, di, id)
on conflict do nothing --CONFLICT
;
$$ language sql;


-- DROP FUNCTION I.contract();


CREATE OR REPLACE FUNCTION I.contract (a bigint, b int, m bigint, d bigint, s bool, de bool, c bigint, p bigint, sc jsonb, bl int)
RETURNS void
AS $$
insert into C.contract --conflict
(address_id, block_hash_id, mgr_id, delegate_id, spendable, delegatable, credit, preorig_id, script, block_level) --conflict
values (a, b, m, d, s, de, c, p, sc, bl) --conflict
on conflict do nothing; --conflict
$$ LANGUAGE SQL;



CREATE OR REPLACE FUNCTION mark_rejected_blocks(howfar int)
returns table(hash char, level integer) as $$
update C.block b
set rejected = true
where not b.rejected
and b.level < (select level from C.block order by level desc limit 1)
and b.level > ((select level from C.block order by level desc limit 1) - howfar)
and (select count(*) from C.block x where x.level > b.level and x.predecessor_id = b.hash_id and not x.rejected) = 0
returning block_hash(b.hash_id), b.level
$$ language sql;



CREATE OR REPLACE FUNCTION balance_at_level(x varchar, lev int)
RETURNS TABLE(bal bigint)
AS $$
select coalesce(
  (SELECT C.balance
   FROM C.contract_balance c, C.block b
   WHERE address_id = address_id(x)
   and C.block_level <= lev
   and C.block_hash_id = b.hash_id
   order by C.block_level desc limit 1
  ),
  0) as bal
$$ LANGUAGE SQL stable;
-- SELECT balance_at_level('tz2FCNBrERXtaTtNX6iimR1UJ5JSDxvdHM93', 1000000);




CREATE OR REPLACE FUNCTION delete_one_operation (xoperation_hash varchar)
returns  void
as $$
select record_log(concat('delete from C.operation where hash = ', xoperation_hash)) where xoperation_hash is not null;
delete from C.operation where hash = xoperation_hash;
$$ language sql;



CREATE OR REPLACE FUNCTION delete_one_block (x varchar)
returns varchar
as $$
select record_log(concat('delete from C.block_hash where hash = ', x)) where x is not null;
delete from C.block_hash where x is not null and hash = x;
select x;
$$ language SQL;



CREATE OR REPLACE FUNCTION delete_rejected_blocks ()
returns integer
as $$
select record_log('delete_rejected_blocks()') where (select count(*) from C.block b where b.rejected) > 0;
select delete_one_block(block_hash(b.hash_id)) as hash from C.block b where b.rejected;
select level from C.block order by level desc limit 1;
$$ language SQL;



CREATE OR REPLACE FUNCTION delete_rejected_blocks_and_above ()
returns integer
as $$
select record_log('delete_rejected_blocks_and_above()');
select delete_one_block(block_hash(b.hash_id)) from C.block b where b.level = (select bb.level from C.block bb where bb.rejected order by level asc limit 1);
select level from C.block order by level desc limit 1;
$$ language SQL;
-- src/db-schema/bigmaps.sql
-- Open Source License
-- Copyright (c) 2019-2021 Nomadic Labs <contact@nomadic-labs.com>
-- Copyright (c) 2021 Philippe Wang <philippe.wang@gmail.com>
--
-- Permission is hereby granted, free of charge, to any person obtaining a
-- copy of this software and associated documentation files (the "Software"),
-- to deal in the Software without restriction, including without limitation
-- the rights to use, copy, modify, merge, publish, distribute, sublicense,
-- and/or sell copies of the Software, and to permit persons to whom the
-- Software is furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included
-- in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
-- THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
-- FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
-- DEALINGS IN THE SOFTWARE.


SELECT 'bigmaps.sql' as file;

DO $$ --SEQONLY
BEGIN --SEQONLY
  IF EXISTS (SELECT * FROM pg_tables WHERE tablename = 'indexer_version') --SEQONLY
     AND EXISTS (SELECT * FROM indexer_version WHERE not multicore) --SEQONLY
     AND EXISTS (SELECT * FROM pg_tables WHERE tablename = 'bigmap' AND schemaname = 'c') --SEQONLY
  THEN --SEQONLY
    ALTER TABLE c.bigmap ALTER COLUMN i TYPE bigint; --SEQONLY
  END IF; --SEQONLY
END; --SEQONLY
$$; --SEQONLY


CREATE TABLE IF NOT EXISTS C.bigmap (
     id bigint
   , "key" jsonb -- key can be null because of allocs
   , key_hash char(54) -- key_hash can be null because key can be null
   , "key_type" jsonb
   , "value" jsonb -- if null, then it means it was deleted, or not filled yet
   , "value_type" jsonb
   , block_hash_id int not null
   , block_level int not null
   , sender_id bigint not null
   , receiver_id bigint not null
   , name text
   , i bigint not null -- i means the i-th bigmapdiff met in the block, except if it comes from a COPY instruction
);
--PKEY bigmap_pkey; C.bigmap; block_hash_id, i --SEQONLY
--FKEY bigmap_block_hash_block_level_fkey; C.bigmap; block_hash_id, block_level; C.block(hash_id, level); CASCADE --SEQONLY
--FKEY bigmap_sender_fkey; C.bigmap; sender_id; C.addresses(address_id); CASCADE --SEQONLY
--FKEY bigmap_receiver_fkey; C.bigmap; receiver_id; C.addresses(address_id); CASCADE --SEQONLY

CREATE INDEX IF NOT EXISTS bigmap_block_hash on C.bigmap using btree (block_hash_id); --SEQONLY
CREATE INDEX IF NOT EXISTS bigmap_block_level on C.bigmap using btree (block_level); --SEQONLY
CREATE INDEX IF NOT EXISTS bigmap_key_hash on C.bigmap using btree (key_hash); --SEQONLY
CREATE INDEX IF NOT EXISTS bigmap_key on C.bigmap using btree ("key"); --SEQONLY
CREATE INDEX IF NOT EXISTS bigmap_name on C.bigmap using btree (name); --SEQONLY
CREATE INDEX IF NOT EXISTS bigmap_id on C.bigmap using btree (id); --SEQONLY
CREATE INDEX IF NOT EXISTS bigmap_sender on C.bigmap using btree (sender_id); --SEQONLY
CREATE INDEX IF NOT EXISTS bigmap_receiver on C.bigmap using btree (receiver_id); --SEQONLY
--OPT CREATE INDEX IF NOT EXISTS bigmap_key_type on C.bigmap using btree ("key_type"); --SEQONLY
--OPT CREATE INDEX IF NOT EXISTS bigmap_value_type on C.bigmap using btree ("value_type"); --SEQONLY



DROP FUNCTION IF EXISTS B.get_by_key_hash;
CREATE OR REPLACE FUNCTION B.get_by_key_hash (xkey_hash char)
returns table (id bigint, "key" jsonb, key_hash char, key_type jsonb, "value" jsonb, value_type jsonb, block_hash char, block_level int, i bigint)
as $$
with r as
(select id, "key", key_hash, key_type, "value", value_type, block_hash(block_hash_id), block_level, i from C.bigmap b where b.key_hash = xkey_hash order by block_level desc, i desc limit 1)
select * from r where "value" is not null;
$$ language SQL stable;


DROP FUNCTION IF EXISTS B.get_by_id;
CREATE OR REPLACE FUNCTION B.get_by_id (xid bigint)
returns table (id bigint, "key" jsonb, key_hash char, key_type jsonb, "value" jsonb, value_type jsonb, block_hash char, block_level int, i bigint)
as $$
with r as
(select id, "key", key_hash, key_type, "value", value_type, block_hash(block_hash_id), block_level, i
 from C.bigmap b where b.id = xid
 and block_level = (select block_level from C.bigmap where id = xid order by block_level desc limit 1) order by i desc)
select * from r where "value" is not null;
$$ language SQL stable;


CREATE OR REPLACE FUNCTION B.assoc (xid bigint, xkey jsonb)
returns table ("key" jsonb, "value" jsonb, block_hash char)
as $$
select "key", "value", block_hash(block_hash_id)
from C.bigmap
where id = xid and "key" = xkey
and block_hash_id = (select b.block_hash_id from C.bigmap b where xkey = b.key order by b.block_level desc limit 1);
$$ language SQL stable;


CREATE OR REPLACE FUNCTION B.update (xid bigint, xkey jsonb, xkey_hash char, xvalue jsonb, xblock_hash int, xblock_level int, xsender bigint, xreceiver bigint, xi smallint)
returns void
as $$
insert into C.bigmap (id, "key", key_hash, "value", block_hash_id, block_level, sender_id, receiver_id, i)
values (xid, xkey, xkey_hash, xvalue, xblock_hash, xblock_level, xsender, xreceiver, xi)
on conflict do nothing; --CONFLICT
$$ language SQL;


CREATE OR REPLACE FUNCTION B.clear (xid bigint, xblock_hash int, xblock_level int, xsender bigint, xreceiver bigint, xi smallint)
returns void
as $$
insert into C.bigmap (id, "key", key_hash, "value", block_hash_id, block_level, sender_id, receiver_id, i)
select xid, b."key", b.key_hash, null, xblock_hash, xblock_level, xsender, xreceiver, xi
from C.bigmap b where b.block_level < xblock_level
on conflict do nothing; --CONFLICT
$$ language SQL;


CREATE OR REPLACE FUNCTION B.alloc (xid bigint, xkey_type jsonb, xvalue_type jsonb, xblock_hash int, xblock_level int, xsender bigint, xreceiver bigint, xi smallint)
returns void
as $$
insert into C.bigmap (id, "key_type", value_type, block_hash_id, block_level, sender_id, receiver_id, i)
values (xid, xkey_type, xvalue_type, xblock_hash, xblock_level, xsender, xreceiver, xi)
on conflict do nothing; --CONFLICT
$$ language SQL;


DROP FUNCTION IF EXISTS B.get_by_id_for_copy;
CREATE OR REPLACE FUNCTION B.get_by_id_for_copy (xid bigint, xblock_level int)
returns table (id bigint, "key" jsonb, key_hash char, key_type jsonb, "value" jsonb, value_type jsonb, block_hash char, block_level int, i bigint)
as $$
with r as
(select id, "key", key_hash, key_type, "value", value_type, block_hash(block_hash_id), block_level, i
 from C.bigmap b where b.id = xid
 and block_level = (select block_level from C.bigmap where id = xid and block_level <= xblock_level order by block_level desc limit 1) order by i desc)
select * from r where "value" is not null;
$$ language SQL stable;

CREATE SEQUENCE IF NOT EXISTS C.bigmap_serial START 1;

DROP FUNCTION IF EXISTS B.copy (bigint, bigint, int, int, bigint, bigint, smallint);
DROP FUNCTION IF EXISTS B.copy (bigint, bigint, int, int, bigint, bigint);

CREATE OR REPLACE FUNCTION B.copy (xid bigint, yid bigint, bhid int, xblock_level int, xsender bigint, xreceiver bigint, i bigint)
returns void
as $$
-- 9 007 199 , 254 740 992
BEGIN
PERFORM setval('c.bigmap_serial', bhid::bigint * 1000000000::bigint + i::bigint * 100000::bigint);
insert into C.bigmap (id, "key", key_hash, "key_type", "value", value_type, block_hash_id, block_level, sender_id, receiver_id, i)
select yid, "key", key_hash, "key_type", "value", value_type, bhid, xblock_level, xsender, xreceiver, -nextval('c.bigmap_serial')
from B.get_by_id_for_copy (xid, xblock_level)
on conflict do nothing;
END;
$$ language PLPGSQL;


-- There is no way for bigmaps to be fully "indexed by segments" because
-- we may record a bigmap copy without having access to the original bigmap.
-- Therefore we create a table that lists blocks having such diffs, so that we may
-- re-run the indexer only on those blocks to properly record copies.


DO $$ --SEQONLY
BEGIN --SEQONLY
  IF EXISTS (SELECT true FROM pg_tables where tablename = 'indexer_version') --SEQONLY
     and exists (select * from indexer_version where not multicore) --SEQONLY
     and exists (select * from pg_tables where tablename = 'C.bigmap_delayed_copies') --SEQONLY
  THEN --SEQONLY
    PERFORM B.copy (xid, yid, bhid, xblock_level, xsender, xreceiver, i) from C.bigmap_delayed_copies order by xblock_level asc; --SEQONLY
    DELETE FROM C.bigmap_delayed_copies; --SEQONLY
  END IF; --SEQONLY
END; --SEQONLY
$$; --SEQONLY
select 'creating block_hash_pkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'block_hash_pkey') THEN
    ALTER TABLE C.block_hash
      ADD CONSTRAINT block_hash_pkey
      PRIMARY KEY (hash);
  END IF;
END;
$$;
select 'creating block_pkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'block_pkey') THEN
    ALTER TABLE C.block
      ADD CONSTRAINT block_pkey
      PRIMARY KEY (hash_id, level);
  END IF;
END;
$$;
select 'creating operation_pkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'operation_pkey') THEN
    ALTER TABLE C.operation
      ADD CONSTRAINT operation_pkey
      PRIMARY KEY (hash_id);
  END IF;
END;
$$;
select 'creating operation_alpha_pkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'operation_alpha_pkey') THEN
    ALTER TABLE C.operation_alpha
      ADD CONSTRAINT operation_alpha_pkey
      PRIMARY KEY (hash_id, id, internal, block_hash_id);
  END IF;
END;
$$;
select 'creating operation_sender_and_receiver_pkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'operation_sender_and_receiver_pkey') THEN
    ALTER TABLE C.operation_sender_and_receiver
      ADD CONSTRAINT operation_sender_and_receiver_pkey
      PRIMARY KEY (operation_id);
  END IF;
END;
$$;
select 'creating proposals_pkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'proposals_pkey') THEN
    ALTER TABLE C.proposals
      ADD CONSTRAINT proposals_pkey
      PRIMARY KEY (proposal);
  END IF;
END;
$$;
select 'creating proposal_pkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'proposal_pkey') THEN
    ALTER TABLE C.proposal
      ADD CONSTRAINT proposal_pkey
      PRIMARY KEY (operation_id, proposal_id);
  END IF;
END;
$$;
select 'creating ballot_pkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ballot_pkey') THEN
    ALTER TABLE C.ballot
      ADD CONSTRAINT ballot_pkey
      PRIMARY KEY (operation_id);
  END IF;
END;
$$;
select 'creating double_endorsement_evidence_pkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'double_endorsement_evidence_pkey') THEN
    ALTER TABLE C.double_endorsement_evidence
      ADD CONSTRAINT double_endorsement_evidence_pkey
      PRIMARY KEY (operation_id);
  END IF;
END;
$$;
select 'creating double_baking_evidence_pkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'double_baking_evidence_pkey') THEN
    ALTER TABLE C.double_baking_evidence
      ADD CONSTRAINT double_baking_evidence_pkey
      PRIMARY KEY (operation_id);
  END IF;
END;
$$;
select 'creating manager_numbers_pkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'manager_numbers_pkey') THEN
    ALTER TABLE C.manager_numbers
      ADD CONSTRAINT manager_numbers_pkey
      PRIMARY KEY (operation_id);
  END IF;
END;
$$;
select 'creating activation_pkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'activation_pkey') THEN
    ALTER TABLE C.activation
      ADD CONSTRAINT activation_pkey
      PRIMARY KEY (operation_id);
  END IF;
END;
$$;
select 'creating endorsement_pkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'endorsement_pkey') THEN
    ALTER TABLE C.endorsement
      ADD CONSTRAINT endorsement_pkey
      PRIMARY KEY (operation_id);
  END IF;
END;
$$;
select 'creating seed_nonce_revelation_pkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'seed_nonce_revelation_pkey') THEN
    ALTER TABLE C.seed_nonce_revelation
      ADD CONSTRAINT seed_nonce_revelation_pkey
      PRIMARY KEY (operation_id);
  END IF;
END;
$$;
select 'creating block_alpha_pkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'block_alpha_pkey') THEN
    ALTER TABLE C.block_alpha
      ADD CONSTRAINT block_alpha_pkey
      PRIMARY KEY (hash_id);
  END IF;
END;
$$;
select 'creating deactivated_pkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'deactivated_pkey') THEN
    ALTER TABLE C.deactivated
      ADD CONSTRAINT deactivated_pkey
      PRIMARY KEY (pkh_id, block_hash_id);
  END IF;
END;
$$;
select 'creating contract_pkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'contract_pkey') THEN
    ALTER TABLE C.contract
      ADD CONSTRAINT contract_pkey
      PRIMARY KEY (address_id, block_hash_id);
  END IF;
END;
$$;
select 'creating contract_balance_pkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'contract_balance_pkey') THEN
    ALTER TABLE C.contract_balance
      ADD CONSTRAINT contract_balance_pkey
      PRIMARY KEY (address_id, block_hash_id);
  END IF;
END;
$$;
select 'creating tx_pkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'tx_pkey') THEN
    ALTER TABLE C.tx
      ADD CONSTRAINT tx_pkey
      PRIMARY KEY (operation_id);
  END IF;
END;
$$;
select 'creating origination_pkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'origination_pkey') THEN
    ALTER TABLE C.origination
      ADD CONSTRAINT origination_pkey
      PRIMARY KEY (operation_id);
  END IF;
END;
$$;
select 'creating delegation_pkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'delegation_pkey') THEN
    ALTER TABLE C.delegation
      ADD CONSTRAINT delegation_pkey
      PRIMARY KEY (operation_id);
  END IF;
END;
$$;
select 'creating reveal_pkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'reveal_pkey') THEN
    ALTER TABLE C.reveal
      ADD CONSTRAINT reveal_pkey
      PRIMARY KEY (operation_id);
  END IF;
END;
$$;
select 'creating balance_updates_block_pkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'balance_updates_block_pkey') THEN
    ALTER TABLE C.balance_updates_block
      ADD CONSTRAINT balance_updates_block_pkey
      PRIMARY KEY (block_hash_id, id);
  END IF;
END;
$$;
select 'creating balance_updates_op_pkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'balance_updates_op_pkey') THEN
    ALTER TABLE C.balance_updates_op
      ADD CONSTRAINT balance_updates_op_pkey
      PRIMARY KEY (operation_id, id);
  END IF;
END;
$$;
select 'creating delegated_contract_pkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'delegated_contract_pkey') THEN
    ALTER TABLE C.delegated_contract
      ADD CONSTRAINT delegated_contract_pkey
      PRIMARY KEY (delegate_id, delegator_id, cycle, level);
  END IF;
END;
$$;
select 'creating bigmap_pkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'bigmap_pkey') THEN
    ALTER TABLE C.bigmap
      ADD CONSTRAINT bigmap_pkey
      PRIMARY KEY (block_hash_id, i);
  END IF;
END;
$$;
select 'creating block_predecessor_id_fkey_s';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'block_predecessor_id_fkey_s') THEN
    ALTER TABLE C.block
      ADD CONSTRAINT block_predecessor_id_fkey_s
      FOREIGN KEY (predecessor_id) REFERENCES C.block(hash_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating operation_block_hash_id_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'operation_block_hash_id_fkey') THEN
    ALTER TABLE C.operation
      ADD CONSTRAINT operation_block_hash_id_fkey
      FOREIGN KEY (block_hash_id) REFERENCES C.block(hash_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating operation_alpha_hash_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'operation_alpha_hash_fkey') THEN
    ALTER TABLE C.operation_alpha
      ADD CONSTRAINT operation_alpha_hash_fkey
      FOREIGN KEY (hash_id) REFERENCES C.operation(hash_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating operation_alpha_block_hash_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'operation_alpha_block_hash_fkey') THEN
    ALTER TABLE C.operation_alpha
      ADD CONSTRAINT operation_alpha_block_hash_fkey
      FOREIGN KEY (block_hash_id) REFERENCES C.block(hash_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating operation_sender_and_receiver_operation_id_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'operation_sender_and_receiver_operation_id_fkey') THEN
    ALTER TABLE C.operation_sender_and_receiver
      ADD CONSTRAINT operation_sender_and_receiver_operation_id_fkey
      FOREIGN KEY (operation_id) REFERENCES C.operation_alpha(autoid)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating operation_sender_and_receiver_sender_id_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'operation_sender_and_receiver_sender_id_fkey') THEN
    ALTER TABLE C.operation_sender_and_receiver
      ADD CONSTRAINT operation_sender_and_receiver_sender_id_fkey
      FOREIGN KEY (sender_id) REFERENCES C.addresses(address_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating operation_sender_and_receiver_receiver_id_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'operation_sender_and_receiver_receiver_id_fkey') THEN
    ALTER TABLE C.operation_sender_and_receiver
      ADD CONSTRAINT operation_sender_and_receiver_receiver_id_fkey
      FOREIGN KEY (receiver_id) REFERENCES C.addresses(address_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating proposal_operation_id_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'proposal_operation_id_fkey') THEN
    ALTER TABLE C.proposal
      ADD CONSTRAINT proposal_operation_id_fkey
      FOREIGN KEY (operation_id) REFERENCES C.operation_alpha(autoid)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating proposal_source_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'proposal_source_fkey') THEN
    ALTER TABLE C.proposal
      ADD CONSTRAINT proposal_source_fkey
      FOREIGN KEY (source_id) REFERENCES C.addresses(address_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating proposal_proposal_id_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'proposal_proposal_id_fkey') THEN
    ALTER TABLE C.proposal
      ADD CONSTRAINT proposal_proposal_id_fkey
      FOREIGN KEY (proposal_id) REFERENCES C.proposals(proposal_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating ballot_operation_id_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ballot_operation_id_fkey') THEN
    ALTER TABLE C.ballot
      ADD CONSTRAINT ballot_operation_id_fkey
      FOREIGN KEY (operation_id) REFERENCES C.operation_alpha(autoid)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating ballot_proposal_id_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ballot_proposal_id_fkey') THEN
    ALTER TABLE C.ballot
      ADD CONSTRAINT ballot_proposal_id_fkey
      FOREIGN KEY (proposal_id) REFERENCES C.proposals(proposal_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating double_endorsement_evidence_operation_id_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'double_endorsement_evidence_operation_id_fkey') THEN
    ALTER TABLE C.double_endorsement_evidence
      ADD CONSTRAINT double_endorsement_evidence_operation_id_fkey
      FOREIGN KEY (operation_id) REFERENCES C.operation_alpha(autoid)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating double_baking_evidence_operation_id_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'double_baking_evidence_operation_id_fkey') THEN
    ALTER TABLE C.double_baking_evidence
      ADD CONSTRAINT double_baking_evidence_operation_id_fkey
      FOREIGN KEY (operation_id) REFERENCES C.operation_alpha(autoid)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating manager_numbers_operation_id_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'manager_numbers_operation_id_fkey') THEN
    ALTER TABLE C.manager_numbers
      ADD CONSTRAINT manager_numbers_operation_id_fkey
      FOREIGN KEY (operation_id) REFERENCES C.operation_alpha(autoid)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating activation_operation_id_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'activation_operation_id_fkey') THEN
    ALTER TABLE C.activation
      ADD CONSTRAINT activation_operation_id_fkey
      FOREIGN KEY (operation_id) REFERENCES C.operation_alpha(autoid)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating activation_pkh_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'activation_pkh_fkey') THEN
    ALTER TABLE C.activation
      ADD CONSTRAINT activation_pkh_fkey
      FOREIGN KEY (pkh_id) REFERENCES C.addresses(address_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating endorsement_operation_id_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'endorsement_operation_id_fkey') THEN
    ALTER TABLE C.endorsement
      ADD CONSTRAINT endorsement_operation_id_fkey
      FOREIGN KEY (operation_id) REFERENCES C.operation_alpha(autoid)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating endorsement_delegate_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'endorsement_delegate_fkey') THEN
    ALTER TABLE C.endorsement
      ADD CONSTRAINT endorsement_delegate_fkey
      FOREIGN KEY (delegate_id) REFERENCES C.addresses(address_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating seed_nonce_revelation_operation_id_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'seed_nonce_revelation_operation_id_fkey') THEN
    ALTER TABLE C.seed_nonce_revelation
      ADD CONSTRAINT seed_nonce_revelation_operation_id_fkey
      FOREIGN KEY (operation_id) REFERENCES C.operation_alpha(autoid)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating block_alpha_hash_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'block_alpha_hash_fkey') THEN
    ALTER TABLE C.block_alpha
      ADD CONSTRAINT block_alpha_hash_fkey
      FOREIGN KEY (hash_id) REFERENCES C.block(hash_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating block_alpha_baker_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'block_alpha_baker_fkey') THEN
    ALTER TABLE C.block_alpha
      ADD CONSTRAINT block_alpha_baker_fkey
      FOREIGN KEY (baker_id) REFERENCES C.addresses(address_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating deactivated_pkh_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'deactivated_pkh_fkey') THEN
    ALTER TABLE C.deactivated
      ADD CONSTRAINT deactivated_pkh_fkey
      FOREIGN KEY (pkh_id) REFERENCES C.addresses(address_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating deactivated_block_hash_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'deactivated_block_hash_fkey') THEN
    ALTER TABLE C.deactivated
      ADD CONSTRAINT deactivated_block_hash_fkey
      FOREIGN KEY (block_hash_id) REFERENCES C.block(hash_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating contract_block_hash_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'contract_block_hash_fkey') THEN
    ALTER TABLE C.contract
      ADD CONSTRAINT contract_block_hash_fkey
      FOREIGN KEY (block_hash_id) REFERENCES C.block(hash_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating contract_mgr_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'contract_mgr_fkey') THEN
    ALTER TABLE C.contract
      ADD CONSTRAINT contract_mgr_fkey
      FOREIGN KEY (mgr_id) REFERENCES C.addresses(address_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating contract_preorig_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'contract_preorig_fkey') THEN
    ALTER TABLE C.contract
      ADD CONSTRAINT contract_preorig_fkey
      FOREIGN KEY (preorig_id) REFERENCES C.addresses(address_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating contract_address_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'contract_address_fkey') THEN
    ALTER TABLE C.contract
      ADD CONSTRAINT contract_address_fkey
      FOREIGN KEY (address_id) REFERENCES C.addresses(address_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating contract_delegate_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'contract_delegate_fkey') THEN
    ALTER TABLE C.contract
      ADD CONSTRAINT contract_delegate_fkey
      FOREIGN KEY (delegate_id) REFERENCES C.addresses(address_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating contract_balance_address_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'contract_balance_address_fkey') THEN
    ALTER TABLE C.contract_balance
      ADD CONSTRAINT contract_balance_address_fkey
      FOREIGN KEY (address_id) REFERENCES C.addresses(address_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating contract_balance_block_hash_block_level_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'contract_balance_block_hash_block_level_fkey') THEN
    ALTER TABLE C.contract_balance
      ADD CONSTRAINT contract_balance_block_hash_block_level_fkey
      FOREIGN KEY (block_hash_id, block_level) REFERENCES C.block(hash_id, level)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating tx_operation_id_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'tx_operation_id_fkey') THEN
    ALTER TABLE C.tx
      ADD CONSTRAINT tx_operation_id_fkey
      FOREIGN KEY (operation_id) REFERENCES C.operation_alpha(autoid)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating tx_source_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'tx_source_fkey') THEN
    ALTER TABLE C.tx
      ADD CONSTRAINT tx_source_fkey
      FOREIGN KEY (source_id) REFERENCES C.addresses(address_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating tx_destination_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'tx_destination_fkey') THEN
    ALTER TABLE C.tx
      ADD CONSTRAINT tx_destination_fkey
      FOREIGN KEY (destination_id) REFERENCES C.addresses(address_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating origination_operation_id_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'origination_operation_id_fkey') THEN
    ALTER TABLE C.origination
      ADD CONSTRAINT origination_operation_id_fkey
      FOREIGN KEY (operation_id) REFERENCES C.operation_alpha(autoid)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating origination_operation_source_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'origination_operation_source_fkey') THEN
    ALTER TABLE C.origination
      ADD CONSTRAINT origination_operation_source_fkey
      FOREIGN KEY (source_id) REFERENCES C.addresses(address_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating origination_k_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'origination_k_fkey') THEN
    ALTER TABLE C.origination
      ADD CONSTRAINT origination_k_fkey
      FOREIGN KEY (k_id) REFERENCES C.addresses(address_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating delegation_operation_id_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'delegation_operation_id_fkey') THEN
    ALTER TABLE C.delegation
      ADD CONSTRAINT delegation_operation_id_fkey
      FOREIGN KEY (operation_id) REFERENCES C.operation_alpha(autoid)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating delegation_source_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'delegation_source_fkey') THEN
    ALTER TABLE C.delegation
      ADD CONSTRAINT delegation_source_fkey
      FOREIGN KEY (source_id) REFERENCES C.addresses(address_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating delegation_pkh_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'delegation_pkh_fkey') THEN
    ALTER TABLE C.delegation
      ADD CONSTRAINT delegation_pkh_fkey
      FOREIGN KEY (pkh_id) REFERENCES C.addresses(address_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating reveal_operation_hash_op_id_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'reveal_operation_hash_op_id_fkey') THEN
    ALTER TABLE C.reveal
      ADD CONSTRAINT reveal_operation_hash_op_id_fkey
      FOREIGN KEY (operation_id) REFERENCES C.operation_alpha(autoid)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating reveal_source_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'reveal_source_fkey') THEN
    ALTER TABLE C.reveal
      ADD CONSTRAINT reveal_source_fkey
      FOREIGN KEY (source_id) REFERENCES C.addresses(address_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating balance_block_block_hash_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'balance_block_block_hash_fkey') THEN
    ALTER TABLE C.balance_updates_block
      ADD CONSTRAINT balance_block_block_hash_fkey
      FOREIGN KEY (block_hash_id) REFERENCES C.block(hash_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating balance_block__contract_address_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'balance_block__contract_address_fkey') THEN
    ALTER TABLE C.balance_updates_block
      ADD CONSTRAINT balance_block__contract_address_fkey
      FOREIGN KEY (contract_address_id) REFERENCES C.addresses(address_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating balance_block_op_operation_id_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'balance_block_op_operation_id_fkey') THEN
    ALTER TABLE C.balance_updates_op
      ADD CONSTRAINT balance_block_op_operation_id_fkey
      FOREIGN KEY (operation_id) REFERENCES C.operation_alpha(autoid)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating balance_contract_address_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'balance_contract_address_fkey') THEN
    ALTER TABLE C.balance_updates_op
      ADD CONSTRAINT balance_contract_address_fkey
      FOREIGN KEY (contract_address_id) REFERENCES C.addresses(address_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating delegated_contract_delegate_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'delegated_contract_delegate_fkey') THEN
    ALTER TABLE C.delegated_contract
      ADD CONSTRAINT delegated_contract_delegate_fkey
      FOREIGN KEY (delegate_id) REFERENCES C.addresses(address_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating delegated_contract_delegator_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'delegated_contract_delegator_fkey') THEN
    ALTER TABLE C.delegated_contract
      ADD CONSTRAINT delegated_contract_delegator_fkey
      FOREIGN KEY (delegator_id) REFERENCES C.addresses(address_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating delegated_contract_cycle_level_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'delegated_contract_cycle_level_fkey') THEN
    ALTER TABLE C.delegated_contract
      ADD CONSTRAINT delegated_contract_cycle_level_fkey
      FOREIGN KEY (cycle, level) REFERENCES C.snapshot(cycle, level)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating bigmap_block_hash_block_level_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'bigmap_block_hash_block_level_fkey') THEN
    ALTER TABLE C.bigmap
      ADD CONSTRAINT bigmap_block_hash_block_level_fkey
      FOREIGN KEY (block_hash_id, block_level) REFERENCES C.block(hash_id, level)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating bigmap_sender_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'bigmap_sender_fkey') THEN
    ALTER TABLE C.bigmap
      ADD CONSTRAINT bigmap_sender_fkey
      FOREIGN KEY (sender_id) REFERENCES C.addresses(address_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
select 'creating bigmap_receiver_fkey';
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'bigmap_receiver_fkey') THEN
    ALTER TABLE C.bigmap
      ADD CONSTRAINT bigmap_receiver_fkey
      FOREIGN KEY (receiver_id) REFERENCES C.addresses(address_id)
      ON DELETE CASCADE;
  END IF;
END;
$$;
-- src/db-schema/mempool.sql
-- Open Source License
-- Copyright (c) 2020 Nomadic Labs <contact@nomadic-labs.com>
--
-- Permission is hereby granted, free of charge, to any person obtaining a
-- copy of this software and associated documentation files (the "Software"),
-- to deal in the Software without restriction, including without limitation
-- the rights to use, copy, modify, merge, publish, distribute, sublicense,
-- and/or sell copies of the Software, and to permit persons to whom the
-- Software is furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included
-- in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
-- THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
-- FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
-- DEALINGS IN THE SOFTWARE.

-- Lines starting with --OPT may be automatically activated
-- Lines ending with --OPT may be automatically deactivated

-- DB schema for operations in the mempool, so you may track the life of an operation

SELECT 'mempool.sql' as file;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'mempool_op_status') THEN
    CREATE TYPE mempool_op_status AS ENUM ('applied', 'refused', 'branch_refused', 'unprocessed', 'branch_delayed');
  END IF;
END
$$;


CREATE TABLE IF NOT EXISTS M.op_branch (
  hash char(51) not null,
  branch char(51) not null,
  primary key(hash)
);


CREATE TABLE IF NOT EXISTS M.operation_alpha (
  hash char(51) not null,
  first_seen_level int not null,
  first_seen_timestamp double precision not null,
  last_seen_level int not null,
  last_seen_timestamp double precision not null,
  status mempool_op_status not null,
  id smallint not null,
  -- index of op in contents_list
  operation_kind smallint not null,
  -- 0: Endorsement
  -- 1: Seed_nonce_revelation
  -- 2: double_endorsement_evidence
  -- 3: Double_baking_evidence
  -- 4: Activate_account
  -- 5: Proposals
  -- 6: Ballot
  -- 7: Manager_operation { operation = Reveal _ ; _ }
  -- 8: Manager_operation { operation = Transaction _ ; _ }
  -- 9: Manager_operation { operation = Origination _ ; _ }
  -- 10: Manager_operation { operation = Delegation _ ; _ }
  source char(36),
  -- sender
  destination char(36),
  -- receiver, if any
  operation_alpha jsonb,
  autoid SERIAL, -- this field should always be last
  primary key(hash, id, status),
  foreign key(source) references C.addresses(address) on delete cascade,
  foreign key(destination) references C.addresses(address) on delete cascade,
  foreign key(hash) references M.op_branch(hash) on delete cascade
);
CREATE INDEX IF NOT EXISTS mempool_operations_hash on M.operation_alpha(hash);
CREATE INDEX IF NOT EXISTS mempool_operations_status on M.operation_alpha(status); --OPT
CREATE INDEX IF NOT EXISTS mempool_operations_source on M.operation_alpha(source);
CREATE INDEX IF NOT EXISTS mempool_operations_destination on M.operation_alpha(destination);
CREATE INDEX IF NOT EXISTS mempool_operations_kind on M.operation_alpha(operation_kind);


-- drop function insert_into_mempool_operation_alpha;

CREATE OR REPLACE FUNCTION M.I_operation_alpha (
  xbranch char(51),
  xlevel int,
  xhash char(51),
  xstatus mempool_op_status,
  xid smallint,
  xoperation_kind smallint,
  xsource char(36),
  xdestination char(36),
  xseen_timestamp double precision,
  xoperation_alpha jsonb
)
returns void
as $$
  insert into C.addresses(address) select xsource where xsource is not null on conflict do nothing;
  insert into C.addresses(address) select xdestination where xdestination is not null on conflict do nothing;
  insert into M.op_branch (hash, branch) values (xhash, xbranch) on conflict do nothing;
  insert into M.operation_alpha (
      hash
    , first_seen_level
    , first_seen_timestamp
    , last_seen_level
    , last_seen_timestamp
    , status
    , id
    , operation_kind
    , source
    , destination
    , operation_alpha
  ) values (
      xhash
    , xlevel
    , xseen_timestamp
    , xlevel
    , xseen_timestamp
    , xstatus
    , xid
    , xoperation_kind
    , xsource
    , xdestination
    , xoperation_alpha
  ) on conflict (hash, id, status)
  do update set
    last_seen_level = xlevel
  , last_seen_timestamp = xseen_timestamp
  where M.operation_alpha.hash = xhash
    and M.operation_alpha.id = xid
    and M.operation_alpha.status = xstatus
$$ language sql;
-- src/mezos-db/db.sql
-- Open Source License
-- Copyright (c) 2018-2020 Nomadic Labs <contact@nomadic-labs.com>
--
-- Permission is hereby granted, free of charge, to any person obtaining a
-- copy of this software and associated documentation files (the "Software"),
-- to deal in the Software without restriction, including without limitation
-- the rights to use, copy, modify, merge, publish, distribute, sublicense,
-- and/or sell copies of the Software, and to permit persons to whom the
-- Software is furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included
-- in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
-- THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
-- FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
-- DEALINGS IN THE SOFTWARE.

-- Lines starting with --OPT may be automatically activated
-- Lines ending with --OPT may be automatically deactivated

SELECT 'mezos.sql' as file;

-- DROP FUNCTION contracts2(character varying);

CREATE OR REPLACE FUNCTION contracts2 (x varchar)
RETURNS TABLE(k char, bal bigint, operation_hash char)
AS $$
SELECT x, coalesce((SELECT balance FROM C.contract_balance WHERE address_id = address_id(x) order by block_level desc limit 1), 0), null
UNION ALL
SELECT
  address(k_id)
, coalesce((SELECT balance FROM C.contract_balance WHERE address_id = k_id order by block_level desc limit 1), 0)
, operation_hash_alpha(operation_id)
FROM C.origination o
WHERE o.source_id = address_id(x)
$$ LANGUAGE SQL stable;


CREATE OR REPLACE FUNCTION latest_balance_by_id (x bigint)
RETURNS TABLE(bal bigint)
AS $$
select coalesce((
SELECT C.balance
FROM C.contract_balance c, C.block b
WHERE C.address_id = x
  and C.block_hash_id = b.hash_id
order by C.block_level desc limit 1
), 0) as bal
$$ LANGUAGE SQL stable;


CREATE OR REPLACE FUNCTION latest_balance (x varchar)
RETURNS TABLE(bal bigint)
AS $$
select latest_balance_by_id(address_id(x)) as bal;
$$ LANGUAGE SQL stable;


-- DROP FUNCTION contracts3;

CREATE OR REPLACE FUNCTION contracts3 (x varchar)
RETURNS TABLE(k char, bal bigint, operation_hash char, delegate char, storage jsonb)
AS $$
SELECT x, (select latest_balance (x)), null, null, null
UNION ALL
SELECT
  address(k_id),
  (select latest_balance_by_id(k_id)),
  operation_hash_alpha(operation_id),
  (select address(delegate_id) from C.contract c2 where c2.delegate_id is not null and c2.address_id = k_id order by c2.block_level desc limit 1),
  (select C.script->'storage' as storage from C.contract c where C.script is not null and C.address_id = k_id order by C.block_level desc limit 1)
FROM C.origination o
WHERE o.source_id = address_id(x) and o.k_id is not null
$$ LANGUAGE SQL stable;


CREATE OR REPLACE FUNCTION manager (x varchar)
RETURNS TABLE(pkh char)
AS $$
select coalesce(
(select address(tx.source_id)
from C.tx tx
where tx.destination_id = address_id(x)
limit 1),
(select address(o.source_id)
from C.origination o
where o.k_id = address_id(x))
)
$$ LANGUAGE SQL stable;



CREATE OR REPLACE FUNCTION get_reveal (address varchar)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
select
       'reveal', -- type
       oa.autoid as id, -- id
       b.level, -- level
       b.timestamp, -- timestamp
       block_hash(b.hash_id),  -- block
       op.hash, -- hash
       address, -- source
       r.fee, -- fees
       m.counter,
       m.gas_limit,
       m.storage_limit,
       oa.id,
       oa.internal, -- internal
       r.nonce, -- nonce
       r.pk, -- public_key (reveal)
       cast(null as bigint), -- amount (tx)
       null, -- destination (tx)
       null, -- parameters (tx)
       null, -- entrypoint (tx)
       null, -- contract_address (origination)
       null  -- delegate (delegation)
from
   C.operation_alpha oa,
   C.block b,
   C.manager_numbers m,
   C.reveal r,
   C.operation op
where
    r.source_id = address_id(address)
AND r.operation_id = oa.autoid
AND op.hash_id = oa.hash_id
AND b.hash_id = op.block_hash_id
AND m.operation_id = oa.autoid
$$ LANGUAGE SQL stable;
-- select * from get_reveal('tz1NKR6nBuLPxSGnFBBTXWLtD2Dt5UAYPWXo') limit 10;
-- select * from get_reveal('tz1LbSsDSmekew3prdDGx1nS22ie6jjBN6B3') limit 10;


CREATE OR REPLACE FUNCTION get_transaction (address varchar)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
select 'transaction', oa.autoid, b.level, b.timestamp, block_hash(b.hash_id), op.hash, address(t.source_id), t.fee,
       m.counter, m.gas_limit, m.storage_limit, oa.id,
       oa.internal,
       t.nonce,
       null,  -- address (reveal)
       t.amount, -- amount (tx)
       address(t.destination_id), -- destination (tx)
       t."parameters", -- parameters (tx)
       t.entrypoint, -- entrypoint (tx)
       null, -- contract_address (origination)
       null -- delegate (delegation)
from C.operation_alpha oa, C.tx t, C.manager_numbers m
, C.operation op
, C.block b
where
    (address_id(address) = t.destination_id or address_id(address) = t.source_id)
AND oa.autoid = t.operation_id
AND op.hash_id = oa.hash_id
AND m.operation_id = oa.autoid
AND b.hash_id = op.block_hash_id
$$ LANGUAGE SQL stable;
-- select * from get_transaction('tz1NKR6nBuLPxSGnFBBTXWLtD2Dt5UAYPWXo') limit 10;
-- select * from get_transaction('tz1LbSsDSmekew3prdDGx1nS22ie6jjBN6B3') limit 10;


CREATE OR REPLACE FUNCTION get_origination (address varchar)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
select
  'origination'
, oa.autoid
, b.level
, b.timestamp
, block_hash(b.hash_id)
, op.hash
, address(o.source_id)
, o.fee
, m.counter
, m.gas_limit
, m.storage_limit
, oa.id
, oa.internal
, o.nonce
, null
, cast(null as bigint) -- amount (tx)
, null -- destination (tx)
, null -- parameters (tx)
, null -- entrypoint (tx)
, address(o.k_id) -- contract_address (origination)
, null -- delegate (delegation)
from C.operation_alpha oa, C.manager_numbers m, C.origination o, C.block b, C.operation op
where
    (address_id(address) = o.source_id or address_id(address) = o.k_id)
and o.operation_id = oa.autoid
AND oa.hash_id = op.hash_id
AND m.operation_id = oa.autoid
and op.block_hash_id = b.hash_id
$$ LANGUAGE SQL stable;
-- select * from get_origination('tz1NKR6nBuLPxSGnFBBTXWLtD2Dt5UAYPWXo') limit 10;


CREATE OR REPLACE FUNCTION get_delegation (address varchar)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
select
  'delegation'
, oa.autoid
, b.level
, b.timestamp
, block_hash(b.hash_id)
, op.hash
, address(d.source_id)
, d.fee
, m.counter
, m.gas_limit
, m.storage_limit
, oa.id
, oa.internal
, d.nonce
, null -- public_key (revelation)
, cast(null as bigint) --amount (tx)
, null -- destination (tx)
, null -- parameters (tx)
, null -- entrypoint (tx)
, null -- contract_address (origination)
, address(pkh_id) -- delegate (delegation)
from C.operation_alpha oa, C.manager_numbers m, C.delegation d, C.block b, C.operation op
where
   (address_id(address) = d.pkh_id or address_id(address) = d.source_id)
AND d.operation_id = oa.autoid
AND m.operation_id = oa.autoid
AND oa.hash_id = op.hash_id
AND op.block_hash_id = b.hash_id
$$ LANGUAGE SQL stable;
-- select * from get_delegation('tz1hGaDz45yCG1AbZqwS653KFDcvmv6jUVqW') limit 10;;
-- select * from get_delegation('tz1LbSsDSmekew3prdDGx1nS22ie6jjBN6B3') limit 10;


CREATE OR REPLACE FUNCTION get_operations (address varchar, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_delegation(address) where id < lastid order by id desc limit lim)
union
(select * from get_origination(address) where id < lastid order by id desc limit lim)
union
(select * from get_transaction(address) where id < lastid order by id desc limit lim)
union
(select * from get_reveal(address)  where id < lastid order by id desc limit lim)
)
order by id desc limit lim
$$ language sql stable;


-- drop function get_operations ;
-- drop function get_transaction ;
-- drop function get_reveal ;
-- drop function get_origination ;
-- drop function get_delegation ;
-- ocaml src/db-schema/mezos_gen_sql_queries.ml
CREATE OR REPLACE FUNCTION get_ops_delegation_origination_reveal_transaction(address varchar, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_delegation(address) where id < lastid order by id desc limit lim)
 union (select * from get_origination(address) where id < lastid order by id desc limit lim)
 union (select * from get_reveal(address) where id < lastid order by id desc limit lim)
 union (select * from get_transaction(address) where id < lastid order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_delegation_origination_reveal(address varchar, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_delegation(address) where id < lastid order by id desc limit lim)
 union (select * from get_origination(address) where id < lastid order by id desc limit lim)
 union (select * from get_reveal(address) where id < lastid order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_delegation_origination_transaction(address varchar, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_delegation(address) where id < lastid order by id desc limit lim)
 union (select * from get_origination(address) where id < lastid order by id desc limit lim)
 union (select * from get_transaction(address) where id < lastid order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_delegation_reveal_transaction(address varchar, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_delegation(address) where id < lastid order by id desc limit lim)
 union (select * from get_reveal(address) where id < lastid order by id desc limit lim)
 union (select * from get_transaction(address) where id < lastid order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_origination_reveal_transaction(address varchar, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_origination(address) where id < lastid order by id desc limit lim)
 union (select * from get_reveal(address) where id < lastid order by id desc limit lim)
 union (select * from get_transaction(address) where id < lastid order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_delegation_origination(address varchar, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_delegation(address) where id < lastid order by id desc limit lim)
 union (select * from get_origination(address) where id < lastid order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_delegation_reveal(address varchar, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_delegation(address) where id < lastid order by id desc limit lim)
 union (select * from get_reveal(address) where id < lastid order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_delegation_transaction(address varchar, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_delegation(address) where id < lastid order by id desc limit lim)
 union (select * from get_transaction(address) where id < lastid order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_origination_reveal(address varchar, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_origination(address) where id < lastid order by id desc limit lim)
 union (select * from get_reveal(address) where id < lastid order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_origination_transaction(address varchar, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_origination(address) where id < lastid order by id desc limit lim)
 union (select * from get_transaction(address) where id < lastid order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_reveal_transaction(address varchar, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_reveal(address) where id < lastid order by id desc limit lim)
 union (select * from get_transaction(address) where id < lastid order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_delegation(address varchar, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_delegation(address) where id < lastid order by id desc limit lim)
)
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_reveal(address varchar, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_reveal(address) where id < lastid order by id desc limit lim)
)
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_transaction(address varchar, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_transaction(address) where id < lastid order by id desc limit lim)
)
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_origination(address varchar, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_origination(address) where id < lastid order by id desc limit lim)
)
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_delegation_origination_reveal_transaction_from(address varchar, "from" timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_delegation(address) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
 union (select * from get_origination(address) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
 union (select * from get_reveal(address) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
 union (select * from get_transaction(address) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_delegation_origination_reveal_from(address varchar, "from" timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_delegation(address) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
 union (select * from get_origination(address) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
 union (select * from get_reveal(address) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_delegation_origination_transaction_from(address varchar, "from" timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_delegation(address) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
 union (select * from get_origination(address) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
 union (select * from get_transaction(address) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_delegation_reveal_transaction_from(address varchar, "from" timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_delegation(address) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
 union (select * from get_reveal(address) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
 union (select * from get_transaction(address) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_origination_reveal_transaction_from(address varchar, "from" timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_origination(address) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
 union (select * from get_reveal(address) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
 union (select * from get_transaction(address) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_delegation_origination_from(address varchar, "from" timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_delegation(address) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
 union (select * from get_origination(address) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_delegation_reveal_from(address varchar, "from" timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_delegation(address) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
 union (select * from get_reveal(address) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_delegation_transaction_from(address varchar, "from" timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_delegation(address) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
 union (select * from get_transaction(address) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_origination_reveal_from(address varchar, "from" timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_origination(address) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
 union (select * from get_reveal(address) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_origination_transaction_from(address varchar, "from" timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_origination(address) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
 union (select * from get_transaction(address) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_reveal_transaction_from(address varchar, "from" timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_reveal(address) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
 union (select * from get_transaction(address) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_delegation_from(address varchar, "from" timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_delegation(address) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
)
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_reveal_from(address varchar, "from" timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_reveal(address) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
)
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_transaction_from(address varchar, "from" timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_transaction(address) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
)
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_origination_from(address varchar, "from" timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_origination(address) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
)
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_delegation_origination_reveal_transaction_downto(address varchar, downto timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_delegation(address) where id < lastid and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_origination(address) where id < lastid and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_reveal(address) where id < lastid and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_transaction(address) where id < lastid and "timestamp" >= downto order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_delegation_origination_reveal_downto(address varchar, downto timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_delegation(address) where id < lastid and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_origination(address) where id < lastid and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_reveal(address) where id < lastid and "timestamp" >= downto order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_delegation_origination_transaction_downto(address varchar, downto timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_delegation(address) where id < lastid and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_origination(address) where id < lastid and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_transaction(address) where id < lastid and "timestamp" >= downto order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_delegation_reveal_transaction_downto(address varchar, downto timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_delegation(address) where id < lastid and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_reveal(address) where id < lastid and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_transaction(address) where id < lastid and "timestamp" >= downto order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_origination_reveal_transaction_downto(address varchar, downto timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_origination(address) where id < lastid and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_reveal(address) where id < lastid and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_transaction(address) where id < lastid and "timestamp" >= downto order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_delegation_origination_downto(address varchar, downto timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_delegation(address) where id < lastid and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_origination(address) where id < lastid and "timestamp" >= downto order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_delegation_reveal_downto(address varchar, downto timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_delegation(address) where id < lastid and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_reveal(address) where id < lastid and "timestamp" >= downto order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_delegation_transaction_downto(address varchar, downto timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_delegation(address) where id < lastid and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_transaction(address) where id < lastid and "timestamp" >= downto order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_origination_reveal_downto(address varchar, downto timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_origination(address) where id < lastid and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_reveal(address) where id < lastid and "timestamp" >= downto order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_origination_transaction_downto(address varchar, downto timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_origination(address) where id < lastid and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_transaction(address) where id < lastid and "timestamp" >= downto order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_reveal_transaction_downto(address varchar, downto timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_reveal(address) where id < lastid and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_transaction(address) where id < lastid and "timestamp" >= downto order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_delegation_downto(address varchar, downto timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_delegation(address) where id < lastid and "timestamp" >= downto order by id desc limit lim)
)
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_reveal_downto(address varchar, downto timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_reveal(address) where id < lastid and "timestamp" >= downto order by id desc limit lim)
)
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_transaction_downto(address varchar, downto timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_transaction(address) where id < lastid and "timestamp" >= downto order by id desc limit lim)
)
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_origination_downto(address varchar, downto timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_origination(address) where id < lastid and "timestamp" >= downto order by id desc limit lim)
)
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_delegation_origination_reveal_transaction_from_downto(address varchar, "from" timestamp, downto timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_delegation(address) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_origination(address) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_reveal(address) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_transaction(address) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_delegation_origination_reveal_from_downto(address varchar, "from" timestamp, downto timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_delegation(address) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_origination(address) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_reveal(address) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_delegation_origination_transaction_from_downto(address varchar, "from" timestamp, downto timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_delegation(address) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_origination(address) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_transaction(address) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_delegation_reveal_transaction_from_downto(address varchar, "from" timestamp, downto timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_delegation(address) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_reveal(address) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_transaction(address) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_origination_reveal_transaction_from_downto(address varchar, "from" timestamp, downto timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_origination(address) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_reveal(address) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_transaction(address) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_delegation_origination_from_downto(address varchar, "from" timestamp, downto timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_delegation(address) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_origination(address) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_delegation_reveal_from_downto(address varchar, "from" timestamp, downto timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_delegation(address) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_reveal(address) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_delegation_transaction_from_downto(address varchar, "from" timestamp, downto timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_delegation(address) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_transaction(address) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_origination_reveal_from_downto(address varchar, "from" timestamp, downto timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_origination(address) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_reveal(address) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_origination_transaction_from_downto(address varchar, "from" timestamp, downto timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_origination(address) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_transaction(address) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_reveal_transaction_from_downto(address varchar, "from" timestamp, downto timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_reveal(address) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_transaction(address) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_delegation_from_downto(address varchar, "from" timestamp, downto timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_delegation(address) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
)
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_reveal_from_downto(address varchar, "from" timestamp, downto timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_reveal(address) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
)
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_transaction_from_downto(address varchar, "from" timestamp, downto timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_transaction(address) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
)
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_origination_from_downto(address varchar, "from" timestamp, downto timestamp, lastid bigint, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
source char,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
internal smallint,
nonce int,
public_key char,
amount bigint,
destination char,
"parameters" char,
entrypoint char,
contract_address char,
delegate char
)
AS $$
((select * from get_origination(address) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
)
$$ language sql;
-- src/db-schema/tokens.sql
-- Open Source License
-- Copyright (c) 2020 Nomadic Labs <contact@nomadic-labs.com>
--
-- Permission is hereby granted, free of charge, to any person obtaining a
-- copy of this software and associated documentation files (the "Software"),
-- to deal in the Software without restriction, including without limitation
-- the rights to use, copy, modify, merge, publish, distribute, sublicense,
-- and/or sell copies of the Software, and to permit persons to whom the
-- Software is furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included
-- in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
-- THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
-- FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
-- DEALINGS IN THE SOFTWARE.

-- Lines starting with --OPT may be automatically activated
-- Lines ending with --OPT may be automatically deactivated

-- DB schema for tokens operations

SELECT 'tokens.sql' as file;



CREATE TABLE IF NOT EXISTS T.contract (
  address_id bigint not null,
  block_hash_id int not null,
  autoid SERIAL UNIQUE
  , primary key(address_id)
  , foreign key(address_id, block_hash_id) references C.contract(address_id, block_hash_id) on delete cascade
  , foreign key(block_hash_id) references C.block(hash_id) on delete cascade
);
--pkey contract_pkey; T.contract; address_id


CREATE OR REPLACE FUNCTION T.I_contract (a bigint, b int)
returns void
as $$
insert into T.contract (address_id, block_hash_id)
values (a, b)
on conflict do nothing; --CONFLICT
$$ language sql;

CREATE INDEX IF NOT EXISTS token_contract_address on T.contract using btree(address_id);
CREATE INDEX IF NOT EXISTS token_contract_block_hash on T.contract using btree(block_hash_id);
CREATE INDEX IF NOT EXISTS token_contract_autoid on T.contract using btree(autoid);



CREATE TABLE IF NOT EXISTS T.balance (
  token_address_id bigint not null,
  address_id bigint not null,
  amount smallint,
  autoid SERIAL UNIQUE
  , primary key (token_address_id, address_id)
  , foreign key (token_address_id) references T.contract(address_id) on delete cascade
  , foreign key (address_id) references C.addresses(address_id) on delete cascade
);

CREATE INDEX IF NOT EXISTS token_balance_token on T.balance using btree(token_address_id);
CREATE INDEX IF NOT EXISTS token_balance_address on T.balance using btree(address_id);
CREATE INDEX IF NOT EXISTS token_balance_autoid on T.balance using btree(autoid);



CREATE OR REPLACE FUNCTION T.I_balance (ta bigint, a bigint, am smallint)
returns void
as $$
-- insert into addresses values (a) on conflict do nothing;
insert into T.balance (token_address_id, address_id, amount)
values (ta, a, am)
on conflict (token_address_id, address_id) do  --CONFLICT
update set amount = am where T.balance.token_address_id = ta and T.balance.address_id = a;  --CONFLICT2
$$ language sql;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'token_operation_kind') THEN
    CREATE TYPE token_operation_kind AS ENUM ('transfer', 'approve', 'getBalance', 'getAllowance', 'getTotalSupply');
  END IF;
END
$$;



CREATE TABLE IF NOT EXISTS T.operation (
  operation_id bigint not null primary key,
  token_address_id bigint not null,
  caller_id bigint not null,
  kind token_operation_kind not null,
  autoid SERIAL UNIQUE, -- this field should always be last
  foreign key (operation_id) references C.operation_alpha(autoid) on delete cascade,
  foreign key (token_address_id) references T.contract(address_id) on delete cascade,
  foreign key (caller_id) references C.addresses(address_id) on delete cascade
);
CREATE INDEX IF NOT EXISTS token_operation_kind    on T.operation using btree (kind); --BOOTSTRAPPED
CREATE INDEX IF NOT EXISTS token_operation_autoid  on T.operation using btree (autoid); --OPT --BOOTSTRAPPED
CREATE INDEX IF NOT EXISTS token_operation_caller  on T.operation using btree (caller_id); --BOOTSTRAPPED
CREATE INDEX IF NOT EXISTS token_operation_address on T.operation using btree (token_address_id); --BOOTSTRAPPED


CREATE OR REPLACE FUNCTION T.I_operation (opaid bigint, ta bigint, c bigint, k token_operation_kind)
returns void
as $$
insert into T.operation
(operation_id, token_address_id, caller_id, kind)
values (opaid, ta, c, k)
on conflict (operation_id) do nothing; --CONFLICT
$$ language sql;



CREATE TABLE IF NOT EXISTS T.transfer (
  operation_id bigint not null primary key,
  source_id bigint not null,
  destination_id bigint not null,
  amount numeric not null,
  autoid SERIAL UNIQUE,
  foreign key (operation_id) references T.operation(operation_id) on delete cascade,
  foreign key (source_id) references C.addresses(address_id) on delete cascade,
  foreign key (destination_id) references C.addresses(address_id) on delete cascade
);

CREATE INDEX IF NOT EXISTS token_transfer_source         on T.transfer using btree (source_id); --BOOTSTRAPPED
CREATE INDEX IF NOT EXISTS token_transfer_destination    on T.transfer using btree (destination_id); --BOOTSTRAPPED
CREATE INDEX IF NOT EXISTS token_transfer_autoid         on T.transfer using btree (autoid); --OPT --BOOTSTRAPPED


CREATE OR REPLACE FUNCTION T.I_transfer (opaid bigint, s bigint, d bigint, a numeric)
returns void
as $$
insert into T.transfer (operation_id, source_id, destination_id, amount)
values (opaid, s, d, a)
on conflict (operation_id) do nothing; --CONFLICT
$$ language sql;



CREATE TABLE IF NOT EXISTS T.approve (
  operation_id bigint not null primary key,
  address_id bigint not null,
  amount numeric not null,
  autoid SERIAL UNIQUE,
  foreign key (operation_id) references T.operation(operation_id) on delete cascade,
  foreign key (address_id) references C.addresses(address_id) on delete cascade
);

CREATE INDEX IF NOT EXISTS token_approve_address           on T.approve using btree (address_id); --BOOTSTRAPPED
CREATE INDEX IF NOT EXISTS token_approve_autoid            on T.approve using btree (autoid); --OPT --BOOTSTRAPPED



CREATE OR REPLACE FUNCTION T.I_approve(opaid bigint, a bigint, am numeric)
returns void
as $$
insert into T.approve (operation_id, address_id, amount)
values (opaid, a, am)
on conflict (operation_id) do nothing --CONFLICT
$$ language sql;


CREATE TABLE IF NOT EXISTS T.get_balance (
  operation_id bigint not null primary key,
  address_id bigint not null,
  callback_id bigint not null,
  autoid SERIAL UNIQUE,
  foreign key (operation_id) references T.operation(operation_id) on delete cascade,
  foreign key (address_id) references C.addresses(address_id) on delete cascade,
  foreign key (callback_id) references C.addresses(address_id) on delete cascade
);


CREATE INDEX IF NOT EXISTS token_get_balance_address           on T.get_balance using btree (address_id); --BOOTSTRAPPED
CREATE INDEX IF NOT EXISTS token_get_balance_callback          on T.get_balance using btree (callback_id); --BOOTSTRAPPED
CREATE INDEX IF NOT EXISTS token_get_balance_autoid            on T.get_balance using btree (autoid); --OPT --BOOTSTRAPPED


CREATE OR REPLACE FUNCTION T.I_get_balance (opaid bigint, a bigint, c bigint)
returns void
as $$
insert into T.get_balance(operation_id, address_id, callback_id)
values (opaid, a, c)
on conflict (operation_id) do nothing; --CONFLICT
$$ language sql;



CREATE TABLE IF NOT EXISTS T.get_allowance (
  operation_id bigint not null primary key,
  source_id bigint not null,
  destination_id bigint not null,
  callback_id bigint not null,
  autoid SERIAL UNIQUE,
  foreign key (operation_id) references T.operation(operation_id) on delete cascade,
  foreign key (source_id) references C.addresses(address_id) on delete cascade,
  foreign key (destination_id) references C.addresses(address_id) on delete cascade,
  foreign key (callback_id) references C.addresses(address_id) on delete cascade
);


CREATE INDEX IF NOT EXISTS token_get_allowance_source            on T.get_allowance using btree (source_id); --BOOTSTRAPPED
CREATE INDEX IF NOT EXISTS token_get_allowance_destination       on T.get_allowance using btree (destination_id); --BOOTSTRAPPED
CREATE INDEX IF NOT EXISTS token_get_allowance_callback          on T.get_allowance using btree (callback_id); --BOOTSTRAPPED
CREATE INDEX IF NOT EXISTS token_get_allowance_autoid            on T.get_balance using btree (autoid); --OPT --BOOTSTRAPPED


CREATE OR REPLACE FUNCTION T.I_get_allowance (opaid bigint, s bigint, d bigint, c bigint)
returns void
as $$
insert into T.get_allowance(operation_id, source_id, destination_id, callback_id)
values (opaid, s, d, c)
on conflict (operation_id) do nothing; --CONFLICT
$$ language sql;


CREATE TABLE IF NOT EXISTS T.get_total_supply (
  operation_id bigint not null primary key,
  callback_id bigint not null,
  autoid SERIAL UNIQUE
  , foreign key (operation_id) references T.operation(operation_id) on delete cascade
  , foreign key (callback_id) references C.addresses(address_id) on delete cascade
);

CREATE INDEX IF NOT EXISTS token_get_total_supply_callback          on T.get_total_supply using btree (callback_id); --BOOTSTRAPPED
CREATE INDEX IF NOT EXISTS token_get_total_supply_autoid            on T.get_total_supply using btree (autoid); --OPT --BOOTSTRAPPED



CREATE OR REPLACE FUNCTION T.I_get_total_supply(opaid bigint, c bigint)
returns void
as $$
insert into T.get_total_supply(operation_id, callback_id)
values (opaid, c)
on conflict (operation_id) do nothing; --CONFLICT
$$ language sql;



CREATE OR REPLACE FUNCTION T.is_token (t bigint)
returns bool
as $$
select exists (select true from T.contract where address_id = t)
$$ language sql stable;
-- src/db-schema/mezos_tokens.sql
-- Open Source License
-- Copyright (c) 2021 Nomadic Labs <contact@nomadic-labs.com>
--
-- Permission is hereby granted, free of charge, to any person obtaining a
-- copy of this software and associated documentation files (the "Software"),
-- to deal in the Software without restriction, including without limitation
-- the rights to use, copy, modify, merge, publish, distribute, sublicense,
-- and/or sell copies of the Software, and to permit persons to whom the
-- Software is furnished to do so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included
-- in all copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
-- THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
-- FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
-- DEALINGS IN THE SOFTWARE.

-- Lines starting with --OPT may be automatically activated
-- Lines ending with --OPT may be automatically deactivated

SELECT 'mezos_tokens.sql' as file;



CREATE OR REPLACE FUNCTION get_token_transfer (address varchar, token varchar)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
caller char,
tz_amount bigint,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
action_source char,
action_destination char,
action_amount numeric,
action_callback char
)
AS $$
with a as (select address_id(address) as ddress)
select 'transfer',
       oa.autoid, -- id
       b.level, -- level
       b.timestamp, -- timestamp
       block_hash(b.hash_id),  -- block
       op.hash, -- hash
       address, -- caller
       t.amount, -- tz_amount
       t.fee, -- fees
       m.counter, m.gas_limit, m.storage_limit, oa.id,
       address(tktx.source_id), -- source (tktx)
       address(tktx.destination_id), -- destination (tktx)
       tktx.amount, -- amount (tktx)
       null -- callback (tktx)
from
       C.operation_alpha oa,
       C.operation op,
       T.operation tkop,
       T.transfer tktx,
       C.block b,
       C.manager_numbers m,
       C.tx t,
       a
where
       (tktx.source_id = a.ddress OR tktx.destination_id = a.ddress)
       and tkop.token_address_id = address_id(token)
       and tkop.operation_id = t.operation_id
       and oa.autoid = t.operation_id
       and op.hash_id = oa.hash_id
       and b.hash_id = op.block_hash_id
       and m.operation_id = oa.autoid
       and tkop.kind = 'transfer'
       and tktx.operation_id = tkop.operation_id
$$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION get_token_approve (address varchar, token varchar)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
caller char,
tz_amount bigint,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
action_source char,
action_destination char,
action_amount numeric,
action_callback char
)
AS $$
with a as (select address_id(address) as ddress)
select 'approve',
       oa.autoid, -- id
       b.level, -- level
       b.timestamp, -- timestamp
       block_hash(b.hash_id),  -- block
       op.hash, -- hash
       address, -- caller
       t.amount, -- tz_amount
       t.fee, -- fees
       m.counter, m.gas_limit, m.storage_limit, oa.id,
       address(tkapp.address_id), -- source (tkapp)
       null, --
       tkapp.amount, -- amount (tkapp)
       null --
from
       C.operation_alpha oa,
       C.operation op,
       T.operation tkop,
       T.approve tkapp,
       C.block b,
       C.manager_numbers m,
       C.tx t,
       a
where
       (tkapp.address_id = a.ddress OR tkop.caller_id = a.ddress)
       and tkop.token_address_id = token_address_id
       and tkop.operation_id = t.operation_id
       and t.operation_id = oa.autoid
       and op.hash_id = oa.hash_id
       and b.hash_id = op.block_hash_id
       and m.operation_id = oa.autoid
       and tkop.kind = 'approve'
       and tkapp.operation_id = tkop.operation_id
$$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION get_token_get_balance (address varchar, token varchar)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
caller char,
tz_amount bigint,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
action_source char,
action_destination char,
action_amount numeric,
action_callback char
)
AS $$
with a as (select address_id(address) as ddress)
select 'getBalance',
       oa.autoid, -- id
       b.level, -- level
       b.timestamp, -- timestamp
       block_hash(b.hash_id),  -- block
       op.hash, -- hash
       address, -- caller
       t.amount, -- tz_amount

       t.fee, -- fees
       m.counter, m.gas_limit, m.storage_limit, oa.id,
       address(tkbal.address_id), -- address (tkbal)
       null, --
       cast(null as numeric), --
       address(tkbal.callback_id) -- amount (tkbal)
from
       C.operation_alpha oa,
       C.operation op,
       T.operation tkop,
       T.get_balance tkbal,
       C.block b,
       C.manager_numbers m,
       C.tx t,
       a
where
       (tkbal.address_id = a.ddress OR tkop.caller_id = a.ddress)
       and tkop.token_address_id = address_id(token)
       and t.operation_id = oa.autoid
       and op.hash_id = oa.hash_id
       and b.hash_id = op.block_hash_id
       and m.operation_id = oa.autoid
       and tkop.operation_id = t.operation_id
       and tkop.kind = 'getBalance'
       and tkbal.operation_id = tkop.operation_id
$$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION get_token_get_allowance (address varchar, token varchar)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
caller char,
tz_amount bigint,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
action_source char,
action_destination char,
action_amount numeric,
action_callback char
)
AS $$
with a as (select address_id(address) as ddress)
select 'getAllowance',
       oa.autoid, -- id
       b.level, -- level
       b.timestamp, -- timestamp
       block_hash(b.hash_id),  -- block
       op.hash, -- hash
       address, -- caller
       t.amount, -- tz_amount
       t.fee, -- fees
       m.counter, m.gas_limit, m.storage_limit, oa.id,
       address(tkalw.source_id), -- source (tkalw)
       address(tkalw.destination_id), -- destination (tkalw)
       cast(null as numeric), --
       address(tkalw.callback_id) -- amount (tkalw)
from
       C.operation_alpha oa,
       C.operation op,
       T.operation tkop,
       T.get_allowance tkalw,
       C.block b,
       C.manager_numbers m,
       C.tx t,
       a
where
       (tkalw.source_id = a.ddress
       OR tkalw.destination_id = a.ddress
       OR tkop.caller_id = a.ddress)
       and tkop.token_address_id = address_id(token)
       and t.operation_id = oa.autoid
       and op.hash_id = oa.hash_id
       and b.hash_id = op.block_hash_id
       and m.operation_id = oa.autoid
       and tkop.operation_id = t.operation_id
       and tkop.kind = 'getAllowance'
       and tkalw.operation_id = tkop.operation_id
$$ LANGUAGE SQL;


CREATE OR REPLACE FUNCTION get_token_get_total_supply (address varchar, token varchar)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
caller char,
tz_amount bigint,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
action_source char,
action_destination char,
action_amount numeric,
action_callback char
)
AS $$
with a as (select address_id(address) as ddress)
select 'getTotalSupply',
       oa.autoid, -- id
       b.level, -- level
       b.timestamp, -- timestamp
       block_hash(b.hash_id),  -- block
       op.hash, -- hash
       address, -- caller
       t.amount, -- tz_amount
       t.fee, -- fees
       m.counter, m.gas_limit, m.storage_limit, oa.id,
       null, --
       null, --
       cast(null as numeric), --
       address(tkts.callback_id) -- amount (tkbal)
from
       C.operation_alpha oa,
       C.operation op,
       T.operation tkop,
       T.get_total_supply tkts,
       C.block b,
       C.manager_numbers m,
       C.tx t,
       a
where
       (tkop.caller_id = a.ddress)
       and tkop.token_address_id = address_id(token)
       and t.operation_id = oa.autoid
       and op.hash_id = oa.hash_id
       and b.hash_id = op.block_hash_id
       and m.operation_id = oa.autoid
       and tkop.operation_id = t.operation_id
       and tkop.kind = 'getTotalSupply'
       and tkts.operation_id = tkop.operation_id
$$ LANGUAGE SQL;
-- ocaml src/db-schema/mezos_tokens_gen_sql_queries.ml
CREATE OR REPLACE FUNCTION get_ops_token_all_operations(address varchar, token varchar, lastid integer, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
caller char,
tz_amount bigint,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
action_source char,
action_destination char,
action_amount numeric,
action_callback char
)
AS $$
((select * from get_token_transfer(address, token) where id < lastid order by id desc limit lim)
 union (select * from get_token_approve(address, token) where id < lastid order by id desc limit lim)
 union (select * from get_token_get_balance(address, token) where id < lastid order by id desc limit lim)
 union (select * from get_token_get_allowance(address, token) where id < lastid order by id desc limit lim)
 union (select * from get_token_get_total_supply(address, token) where id < lastid order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_token_transfer_approve(address varchar, token varchar, lastid integer, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
caller char,
tz_amount bigint,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
action_source char,
action_destination char,
action_amount numeric,
action_callback char
)
AS $$
((select * from get_token_transfer(address, token) where id < lastid order by id desc limit lim)
 union (select * from get_token_approve(address, token) where id < lastid order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_token_transfer(address varchar, token varchar, lastid integer, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
caller char,
tz_amount bigint,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
action_source char,
action_destination char,
action_amount numeric,
action_callback char
)
AS $$
((select * from get_token_transfer(address, token) where id < lastid order by id desc limit lim)
)
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_token_approve(address varchar, token varchar, lastid integer, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
caller char,
tz_amount bigint,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
action_source char,
action_destination char,
action_amount numeric,
action_callback char
)
AS $$
((select * from get_token_approve(address, token) where id < lastid order by id desc limit lim)
)
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_token_all_operations_from(address varchar, token varchar, "from" timestamp, lastid integer, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
caller char,
tz_amount bigint,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
action_source char,
action_destination char,
action_amount numeric,
action_callback char
)
AS $$
((select * from get_token_transfer(address, token) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
 union (select * from get_token_approve(address, token) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
 union (select * from get_token_get_balance(address, token) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
 union (select * from get_token_get_allowance(address, token) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
 union (select * from get_token_get_total_supply(address, token) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_token_transfer_approve_from(address varchar, token varchar, "from" timestamp, lastid integer, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
caller char,
tz_amount bigint,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
action_source char,
action_destination char,
action_amount numeric,
action_callback char
)
AS $$
((select * from get_token_transfer(address, token) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
 union (select * from get_token_approve(address, token) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_token_transfer_from(address varchar, token varchar, "from" timestamp, lastid integer, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
caller char,
tz_amount bigint,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
action_source char,
action_destination char,
action_amount numeric,
action_callback char
)
AS $$
((select * from get_token_transfer(address, token) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
)
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_token_approve_from(address varchar, token varchar, "from" timestamp, lastid integer, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
caller char,
tz_amount bigint,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
action_source char,
action_destination char,
action_amount numeric,
action_callback char
)
AS $$
((select * from get_token_approve(address, token) where id < lastid and "timestamp" <= "from" order by id desc limit lim)
)
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_token_all_operations_downto(address varchar, token varchar, downto timestamp, lastid integer, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
caller char,
tz_amount bigint,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
action_source char,
action_destination char,
action_amount numeric,
action_callback char
)
AS $$
((select * from get_token_transfer(address, token) where id < lastid and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_token_approve(address, token) where id < lastid and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_token_get_balance(address, token) where id < lastid and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_token_get_allowance(address, token) where id < lastid and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_token_get_total_supply(address, token) where id < lastid and "timestamp" >= downto order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_token_transfer_approve_downto(address varchar, token varchar, downto timestamp, lastid integer, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
caller char,
tz_amount bigint,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
action_source char,
action_destination char,
action_amount numeric,
action_callback char
)
AS $$
((select * from get_token_transfer(address, token) where id < lastid and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_token_approve(address, token) where id < lastid and "timestamp" >= downto order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_token_transfer_downto(address varchar, token varchar, downto timestamp, lastid integer, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
caller char,
tz_amount bigint,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
action_source char,
action_destination char,
action_amount numeric,
action_callback char
)
AS $$
((select * from get_token_transfer(address, token) where id < lastid and "timestamp" >= downto order by id desc limit lim)
)
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_token_approve_downto(address varchar, token varchar, downto timestamp, lastid integer, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
caller char,
tz_amount bigint,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
action_source char,
action_destination char,
action_amount numeric,
action_callback char
)
AS $$
((select * from get_token_approve(address, token) where id < lastid and "timestamp" >= downto order by id desc limit lim)
)
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_token_all_operations_from_downto(address varchar, token varchar, "from" timestamp, downto timestamp, lastid integer, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
caller char,
tz_amount bigint,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
action_source char,
action_destination char,
action_amount numeric,
action_callback char
)
AS $$
((select * from get_token_transfer(address, token) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_token_approve(address, token) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_token_get_balance(address, token) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_token_get_allowance(address, token) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_token_get_total_supply(address, token) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_token_transfer_approve_from_downto(address varchar, token varchar, "from" timestamp, downto timestamp, lastid integer, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
caller char,
tz_amount bigint,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
action_source char,
action_destination char,
action_amount numeric,
action_callback char
)
AS $$
((select * from get_token_transfer(address, token) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
 union (select * from get_token_approve(address, token) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
)
order by id desc limit lim
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_token_transfer_from_downto(address varchar, token varchar, "from" timestamp, downto timestamp, lastid integer, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
caller char,
tz_amount bigint,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
action_source char,
action_destination char,
action_amount numeric,
action_callback char
)
AS $$
((select * from get_token_transfer(address, token) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
)
$$ language sql;
CREATE OR REPLACE FUNCTION get_ops_token_approve_from_downto(address varchar, token varchar, "from" timestamp, downto timestamp, lastid integer, lim integer)
RETURNS TABLE(
type text,
id bigint,
level int,
"timestamp" timestamp,
block char,
hash char,
caller char,
tz_amount bigint,
fee bigint,
counter numeric,
gas_limit numeric,
storage_limit numeric,
op_id smallint,
action_source char,
action_destination char,
action_amount numeric,
action_callback char
)
AS $$
((select * from get_token_approve(address, token) where id < lastid and "timestamp" <= "from" and "timestamp" >= downto order by id desc limit lim)
)
$$ language sql;
insert into c.block_hash values ('BMduXQshc6QuoSzD6Q4qFDFkZzvtPNuiaTPe8AksXtpPNSqKARn', 0);
insert into c.block_hash values ('BLLARW12mytmxm9LDjs36SkXZxEqoGLzhY9A69RpdahwWqogRmz', 1);

