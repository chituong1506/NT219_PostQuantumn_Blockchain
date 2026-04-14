package com.nt219.ksm;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;

/**
 * KSM (Key Simulation Module) Application
 * 
 * REST API service for Post-Quantum Cryptography operations:
 * - Key generation (Dilithium)
 * - Transaction signing
 * - Signature verification
 */
@SpringBootApplication
public class KSMApplication {

    public static void main(String[] args) {
        System.out.println("===========================================");
        System.out.println("   KSM - Key Simulation Module");
        System.out.println("   Post-Quantum Cryptography Service");
        System.out.println("===========================================");
        SpringApplication.run(KSMApplication.class, args);
    }
}

