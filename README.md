# F5 module
Based off the f5 module from puppetlabs (https://github.com/puppetlabs/puppetlabs-f5)

## Overview

This is based on the puppetlabs-f5 module, amongst others it adds the following extras:

- Support for F5 V11+. **As of writing the puppetlabs-f5 module also has added V11 support**
- Prefetch methods.
- F5 transactions and provider flush methods for atomic changes (where possible).
- Partition support per resource.
- Autorequirement of dependencies.

Supported resources:

- f5_file
- f5_irule
- f5_node
- f5_partition
- f5_pool
- f5_poolmember
- f5_virtualserver

## Usage

1. Create F5 Device configuration file in $confdir/device.conf (typically /etc/puppet/device.conf or /etc/puppetlabs/puppet/device.conf)

        [f5.example.com]
        type f5
        url https://username:password@address/

2. Create the corresponding node configuration on the puppet master site.pp:

        node f5.example.com {

          f5_partition { '/TestPartition2000': }
        
          f5_pool { '/TestPartition2000/TestPool2000':
            lb_method       => 'ratio_member',
            health_monitors => ['/Common/https', '/Common/http'],
            members         => [
              {'address' => '/TestPartition2000/TestNode2001', 'port' => 80},
              {'address' => '/TestPartition2000/TestNode2002', 'port' => 80},
              {'address' => '/TestPartition2000/TestNode2003', 'port' => 80},
              {'address' => '/TestPartition2000/TestNode2004', 'port' => 80},
            ]
          }
        
          f5_node {
            '/TestPartition2000/TestNode2000':
              connection_limit => 1,
              dynamic_ratio    => '1',
              ipaddress        => '1.1.1.97',
              rate_limit       => 1,
              ratio            => 1,
              session_status   => 'ENABLED';
            '/TestPartition2000/TestNode2001':
              ipaddress => '2.2.2.2';
          }
        
          f5_poolmember { '/TestPartition2000/TestNode2000':
            port        => 443,
            pool        => '/TestPartition2000/TestPool2000',
            ratio       => 2;
          }
        
          f5_poolmember { '/TestPartition2000/TestPool2000:/TestPartition2000/TestNode2001':
            port             => 443,
            connection_limit => 100,
            ratio            => 7;
          }
        
          f5_irule { '/TestPartition2000/TestRule2000':
            definition => '#Empty';
          }
        
          f5_virtualserver { '/TestPartition2000/TestVirtualServer2000':
            address                      => '1.2.3.4',
            default_pool                 => '/TestPartition2000/TestPool2000',
            port                         => '443',
            profiles                     => ['/Common/http', '/Common/clientssl', '/Common/serverssl'],
            protocol                     => 'TCP';
          }
        }

3. Execute puppet device command:

        $ puppet device

4. To test from commandline:

        $ FACTER_url=https://admin:admin@f5.example.com/ puppet resource f5_irule
