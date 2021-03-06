require_relative './helper'

DB = Hash[database_config.collect { |db, config| [ db, Sequel.connect(config) ] }]

{
  default: %w[ db_default_a_models db_default_b_models ],
  a: %w[ example_as ],
  b: %w[ example_bs ]
}.each do |db, tables|
  create_config = database_config[db].dup
  db_name = create_config.delete(:database)
  
  handle = Mysql2::Client.new(create_config)

  db_name = database_config[db][:database]
  
  handle.query("DROP DATABASE IF EXISTS `#{db_name}`")
  handle.query("CREATE DATABASE `#{db_name}`")
  handle.query("USE `#{db_name}`")

  tables.each do |table|
    handle.query("CREATE TABLE `#{table}` (id INT AUTO_INCREMENT PRIMARY KEY, data VARCHAR(255))")
  end
end

class DbDefaultAModel < Sequel::Model
end

class DbDefaultBModel < Sequel::Model
end

class DbAModel < Sequel::Model(DB[:a][:example_as])
end

class DbBModel < Sequel::Model(DB[:b][:example_bs])
end

class TestEmSequelAsync < Test::Unit::TestCase
  def test_module
    assert EmSequelAsync
  end
  
  def test_async_db_handle
    assert DbDefaultAModel.db
    assert DbDefaultAModel.db.async
    
    assert_equal DbDefaultAModel.db, DbDefaultBModel.db
    assert_not_equal DbAModel.db, DbDefaultBModel.db
    assert_not_equal DbAModel.db, DbBModel.db
    
    assert_equal DbDefaultAModel.db.async, DbDefaultBModel.db.async
    assert_not_equal DbAModel.db.async, DbDefaultBModel.db.async
    assert_not_equal DbAModel.db.async, DbBModel.db.async
  end

  def test_model_async_insert
    inserted_id = nil
    
    em do
      await do
        DbDefaultAModel.async_insert(
          data: 'Test Name',
          &defer do |id|
            inserted_id = id
          end
        )

        assert_equal nil, inserted_id
      end
    end

    assert inserted_id
    assert inserted_id > 0
  end
  
  def test_model_async_insert_ignore
    inserted_id = nil
    inserted_count = nil
    found_count = nil
    deleted_count = nil

    em do
      await do
        DbDefaultAModel.async_insert(
          data: 'Test Name',
          &defer do |id|
            inserted_id = id
            
            assert inserted_id > 0

            DbDefaultAModel.where(id: inserted_id).async_count(
              &defer do |count|
                found_count = count
              end
            )

            DbDefaultAModel.async_insert_ignore(
              id: inserted_id,
              data: 'Duplicate',
              &defer do |count|
                inserted_count = count
              end
            )
          end
        )
      end
      
      assert_equal 0, inserted_count
      assert_equal 1, found_count
    end
    
    em do
      found_count = nil
      deleted_count = nil
      inserted_count = nil
      
      await do |a|
        DbDefaultAModel.where(id: inserted_id).async_delete(
          &defer do |count|
            deleted_count = count
            
            assert_equal 1, deleted_count

            DbDefaultAModel.where(id: inserted_id).async_count(
              &defer do |_count|
                found_count = _count

                DbDefaultAModel.async_insert_ignore(
                  id: inserted_id,
                  data: 'Duplicate',
                  &defer do |__count|
                    inserted_count = __count
                  end
                )
              end
            )
          end
        )
      end
    end
    
    assert_equal 0, found_count
    assert_equal 1, deleted_count
    assert_equal 1, inserted_count
  end
  
  def test_dataset_async_count
    models_count = nil
    
    em do
      await do
        DB[:default][:db_default_a_models].async_count(
          &defer do |count|
            models_count = count
          end
        )
      end
    end
    
    assert_equal DB[:default][:db_default_a_models].count, models_count
  end

  def test_dataset_async_insert_duplicate
    em do
      inserted_id = nil
      duplicate_id = false
      
      await do
        DbDefaultAModel.async_insert(
          data: 'Test Name',
          &defer do |id|
            inserted_id = id
            
            DbDefaultAModel.async_insert(
              id: inserted_id,
              data: 'Duplicate',
              &defer do |*f|
                duplicate_id = f[0]
              end
            )
          end
        )
      end
      
      assert inserted_id
      assert_equal nil, duplicate_id
    end
  end
end
